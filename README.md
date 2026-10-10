# Dual NVIDIA CMP 50HX (20 GB) UEFI compute unlock — step-by-step guide

**[Русская инструкция](README.md)** · **[Benchmark results](docs/RESULTS.md)** · **[Troubleshooting](docs/TROUBLESHOOTING.md)** · **[Credits and licensing](docs/ATTRIBUTION.md)**

This guide shows the **exact commands** to build two independent UEFI unlock applications, run them sequentially from GRUB, validate both GPUs with OpenCL `clpeak`, and enable automatic unlocking before Linux starts. **No NVIDIA driver patch or VBIOS flashing is required for this compute-unlock workflow.**

The original UEFI unlock logic, GSP/SEC2 implementation, and firmware payloads come from [xrip/cmp50hx-unlock](https://github.com/xrip/cmp50hx-unlock). This repository supplies only the two-GPU selection/orchestration scripts, GRUB/systemd configuration, documentation, and observed test results. It does **not** redistribute upstream source files, firmware blobs, or ready-made EFI binaries.

> **Hardware warning:** experimental EFI code can hang the system before Linux boots. Perform the first test only with **physical console access**, a fallback boot path, and the ability to completely power off the machine. Do not test an unverified bootloader on a remote-only server.

## Tested setup and results

| Measurement | CMP 50HX GPU 0 | CMP 50HX GPU 1 |
|---|---:|---:|
| OpenCL FP32, locked | 0.427 TFLOPS | 0.427 TFLOPS |
| OpenCL FP32, unlocked | **13.5 TFLOPS** | **13.5 TFLOPS** |
| FP32 speedup | ~31.6× | ~31.6× |
| VRAM | 20 GB | 20 GB |
| PCIe observed | Gen1 x4 | Gen1 x16 |

**Validated 2026-10-10 on:** Machinist X99-D8 Max, 2× Xeon E5-2680 v4, Kali Rolling kernel `7.1.5+kali-amd64`, NVIDIA driver/GSP `615.71.09`, 2× CMP 50HX (`10de:1e09`, subsystem `10de:1554`), UEFI + GRUB. An RX 5700 XT was also installed for display output.

Both GPUs were unlocked in one GRUB boot sequence and the one-shot automatic selection was observed working on this machine. **Not yet validated:** complete cold power-off/power-on, relocation to different PCIe slots, other card revisions, Gen2, long-duration LLM workloads, or FP16/Tensor Core throughput. The GPUs expose **two separate 20 GB memory pools**, not one 40 GB pool. `clpeak`'s `float16` row is a vector of FP32 elements, not an FP16 measurement.

## 1. Check prerequisites

The following commands assume **Kali Linux** and a **root shell**. Distribution-specific paths/packages may differ elsewhere.

```bash
sudo -i

# Ensure UEFI mode
[ -d /sys/firmware/efi ] && echo 'UEFI OK' || echo 'ERROR: Legacy boot'

# Find both supported GPU devices
lspci -Dnn | grep -i '10de:1e09'
nvidia-smi -L
nvidia-smi --query-gpu=index,name,pci.bus_id,vbios_version,memory.total --format=csv

# Ensure the EFI System Partition is mounted and GRUB exists
findmnt /boot/efi
efibootmgr -v | grep -E '^BootCurrent:|^BootOrder:|kali|GRUB'
```

Stop if you cannot identify two compatible CMP 50HX cards, a functioning NVIDIA driver, a working GRUB UEFI entry, and the mounted EFI System Partition (ESP).

## 2. Back up the current boot configuration

```bash
mkdir -p /root/cmp50hx-backup
cp -a /etc/default/grub /root/cmp50hx-backup/grub-default.before
cp -a /boot/grub/grub.cfg /root/cmp50hx-backup/grub.cfg.before
efibootmgr -v > /root/cmp50hx-backup/efibootmgr.before.txt

# Preserve an existing working unlocker, if present
if [ -f /boot/efi/EFI/50HX/50HXUNLK.EFI ]; then
  cp -a /boot/efi/EFI/50HX/50HXUNLK.EFI \
    /root/cmp50hx-backup/50HXUNLK.original.EFI
fi

if [ -f /boot/efi/50hx_log.txt ]; then
  cp -a /boot/efi/50hx_log.txt /root/cmp50hx-backup/
fi

ls -lh /root/cmp50hx-backup/
```

**Do not overwrite** an existing `/boot/efi/EFI/50HX/50HXUNLK.EFI`. The next steps install to separate `50HX-AUTO0` and `50HX-AUTO1` directories.

## 3. Install dependencies and clone repositories

```bash
apt update
apt install -y git build-essential gnu-efi binutils python3 file \
  pciutils efibootmgr cmake clinfo ocl-icd-opencl-dev

cd /root

# Replace YOUR_GITHUB_USERNAME with the owner of your published repository.
# If using a downloaded ZIP, extract it to /root/cmp50hx-dual-gpu-unlock instead.
git clone https://github.com/YOUR_GITHUB_USERNAME/cmp50hx-dual-gpu-unlock.git

# Original UEFI unlock project (skip clone if it already exists)
git clone https://github.com/xrip/cmp50hx-unlock.git cmp50hx-unlock-src

# Record exact upstream revision for reproducibility
git -C /root/cmp50hx-unlock-src rev-parse HEAD
```

Expected paths:

```text
/root/cmp50hx-dual-gpu-unlock/scripts/build-dual.sh
/root/cmp50hx-unlock-src/efi-unlock/unlock50x_v1.c
```

The upstream project can change. The patcher intentionally fails if expected source anchors are missing; investigate upstream differences instead of bypassing these checks.

## 4. Build both EFI applications (build-only)

```bash
cd /root/cmp50hx-dual-gpu-unlock

bash scripts/build-dual.sh \
  /root/cmp50hx-unlock-src/efi-unlock \
  /root/cmp50hx-dual-gpu-unlock/dist
```

Expected final message:

```text
BUILD_DUAL_OK (not installed)
```

Validate both files:

```bash
file dist/50HX-AUTO0.EFI dist/50HX-AUTO1.EFI
objdump -p dist/50HX-AUTO0.EFI | grep -i Subsystem
objdump -p dist/50HX-AUTO1.EFI | grep -i Subsystem
sha256sum dist/50HX-AUTO*.EFI
ls -lh dist/
```

Both should be **PE32+ EFI applications** with subsystem `0x0A`. The script adjusts Kali's multiarch `gnu-efi` library path and the modern `objcopy --output-target` invocation inside a **temporary upstream copy**. It does **not** modify the ESP, boot settings, VBIOS, or installed NVIDIA driver.

`AUTO0` targets the first compatible device found; `AUTO1` targets the second. Unlike the initial BDF-specific experiment, the PCI bus numbers are not hard-coded, but compatibility after moving or replacing cards is not yet validated.

## 5. Install the EFI files into isolated ESP directories

```bash
findmnt /boot/efi

mkdir -p /boot/efi/EFI/50HX-AUTO0 /boot/efi/EFI/50HX-AUTO1

install -m 0644 dist/50HX-AUTO0.EFI \
  /boot/efi/EFI/50HX-AUTO0/50HXUNLK.EFI
install -m 0644 dist/50HX-AUTO1.EFI \
  /boot/efi/EFI/50HX-AUTO1/50HXUNLK.EFI

sha256sum dist/50HX-AUTO*.EFI
sha256sum /boot/efi/EFI/50HX-AUTO{0,1}/50HXUNLK.EFI
sync
```

Compare the checksums of each source/destination pair. The previous working EFI remains untouched.

## 6. Add a separate GRUB menu entry

```bash
cd /root/cmp50hx-dual-gpu-unlock
install -m 0755 grub/42_cmp50_auto /etc/grub.d/42_cmp50_auto
nano /etc/default/grub
```

Ensure these settings occur **once each**:

```ini
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=10
```

`GRUB_DEFAULT=0` is correct **only if the first item is your normal Kali boot**. Otherwise select your regular Kali entry explicitly. **Never set `GRUB_DEFAULT=cmp50-auto`**, because this entry loads the GRUB configuration again after the EFI applications return.

```bash
update-grub
grub-script-check /boot/grub/grub.cfg
grep -A25 "menuentry 'CMP 50HX AUTO" /boot/grub/grub.cfg
```

The new item is `CMP 50HX AUTO - BOTH GPUs`. It runs the two EFI applications sequentially with `--return-to-grub`, then opens the regular Kali menu.

## 7. Perform the mandatory manual test

```bash
# Disable previously scheduled automatic entry, if any
systemctl disable --now cmp50-auto-boot.service 2>/dev/null || true
grub-editenv /boot/grub/grubenv unset next_entry

# Identify the *actual* Kali GRUB BootXXXX number
efibootmgr -v | grep -E '^Boot[0-9A-Fa-f]{4}\*.*(kali|Kali|GRUB)'
```

On the reference machine Kali GRUB was `Boot0001`. **Replace `0001` with your own entry ID**:

```bash
KALI_BOOT_ID=0001

efibootmgr -n "$KALI_BOOT_ID"
efibootmgr | grep -E '^BootNext:|^BootOrder:'
sync
reboot
```

At the **first GRUB menu**, manually select **CMP 50HX AUTO - BOTH GPUs**. Once both EFI applications return and the standard GRUB menu appears, select **normal Kali Linux** (do not run the unlock entry twice).

### Measure both GPUs with clpeak

If `clpeak` is not already installed, build it:

```bash
cd /root
git clone https://github.com/krrishnarraj/clpeak.git
cmake -S /root/clpeak -B /root/clpeak/build
cmake --build /root/clpeak/build -j4
```

Then run:

```bash
/root/clpeak/build/clpeak --opencl --single-precision-compute

journalctl -k -b --no-pager | grep -E 'NVRM: Xid|GPU has fallen off' || true
bash /root/cmp50hx-dual-gpu-unlock/scripts/verify.sh
```

**Pass criterion on the tested setup:** both CMP devices produce approximately **13.5 TFLOPS FP32** each. If both remain around 0.427 TFLOPS, or only one is unlocked, **do not enable automatic boot**; use [Troubleshooting](docs/TROUBLESHOOTING.md). The second EFI may overwrite `50hx_log.txt`, so the two `clpeak` results are the primary evidence.

## 8. Enable automatic unlock on each boot

**Only after step 7 passes.** The systemd oneshot service calls `grub-reboot cmp50-auto` to schedule the unlock entry for the *next* GRUB boot; Linux re-arms it after each successful startup.

```bash
cd /root/cmp50hx-dual-gpu-unlock

install -m 0644 systemd/cmp50-auto-boot.service \
  /etc/systemd/system/cmp50-auto-boot.service

systemctl daemon-reload
systemctl enable --now cmp50-auto-boot.service
systemctl status cmp50-auto-boot.service --no-pager
grub-editenv /boot/grub/grubenv list
```

Expected output includes:

```text
ExecStart=/usr/sbin/grub-reboot cmp50-auto (status=0/SUCCESS)
Active: inactive (dead)
next_entry=cmp50-auto
```

`inactive (dead)` is normal for a completed **oneshot** unit. `next_entry` reports the **next** boot selection, not proof of unlocking during the current boot.

### Make Kali GRUB the first UEFI boot option

```bash
efibootmgr -v
```

Identify the actual `BootXXXX` ID for **Kali GRUB**. If Kali is not already first, move that ID to the front, preserving the other entries:

```bash
KALI_BOOT_ID=0001    # REPLACE with the actual Kali GRUB BootXXXX ID

efibootmgr -v | grep -E "^Boot${KALI_BOOT_ID}[*]" || {
  echo 'Incorrect Boot ID; stopping'; exit 1;
}

CURRENT_ORDER=$(efibootmgr | sed -n 's/^BootOrder: //p')
REST=$(printf '%s\n' "$CURRENT_ORDER" | tr ',' '\n' | \
  grep -v -x "$KALI_BOOT_ID" | paste -sd, -)

efibootmgr -o "${KALI_BOOT_ID},${REST}"
efibootmgr | grep -E '^BootOrder:|^BootNext:'
```

Verify that **Kali GRUB**, not Windows Boot Manager, is now first. Then:

```bash
sync
reboot
```

At the **first** GRUB menu do nothing: the one-shot default should select `CMP 50HX AUTO - BOTH GPUs`. At the **second** menu, boot normal Kali (automatically if the regular default is configured). Once Linux starts, run `clpeak` again.

## 9. Verify subsequent boots / hardware changes

```bash
nvidia-smi -L
/root/clpeak/build/clpeak --opencl --single-precision-compute
systemctl status cmp50-auto-boot.service --no-pager
grub-editenv /boot/grub/grubenv list

echo '=== PCIe ==='
for GPU in 03:00.0 84:00.0; do
  lspci -s "$GPU" -vv | grep -E 'LnkCap:|LnkSta:'
done
nvidia-smi topo -m
```

The PCI addresses above are **examples from the tested host**; enumerate the current BDF values with `lspci -Dnn` after moving cards. This project does **not** unlock PCIe Gen2, provide NVLink, or merge VRAM. The reference test still showed PCIe Gen1 x4 and x16.

## 10. Disable automatic unlock / roll back

Disable the next scheduled automatic unlock **without deleting EFI files**:

```bash
systemctl disable --now cmp50-auto-boot.service
grub-editenv /boot/grub/grubenv unset next_entry
grub-editenv /boot/grub/grubenv list
```

Optionally remove the experimental GRUB entry:

```bash
rm -f /etc/grub.d/42_cmp50_auto
update-grub
grub-script-check /boot/grub/grub.cfg
```

Restore `/etc/default/grub` **only from your own backup**, if needed:

```bash
cp -a /root/cmp50hx-backup/grub-default.before /etc/default/grub
update-grub
```

If UEFI hangs before Linux loads, shell commands cannot recover it: use the physical console, an alternative boot entry, and if required a **full power cycle**. Do not remove the original `/EFI/50HX/` directory.

## Troubleshooting quick reference

| Symptom | What to check |
|---|---|
| `elf_x86_64_efi.lds: No such file` | Install `gnu-efi`; builder uses Kali's `/usr/lib/x86_64-linux-gnu` |
| `objcopy: file format not recognized` | `--output-target=efi-app-x86_64`; builder patches the temporary `build.sh` |
| Both GPUs around 427 GFLOPS after reboot | Verify GRUB actually ran `cmp50-auto`, then review EFI logs |
| Only one GPU around 13.5 TFLOPS | Verify both generated EFI files and both GRUB chainloader calls |
| systemd says `inactive (dead)` | Normal for a completed oneshot with successful exit code |
| Different PCI addresses after moving boards | Re-enumerate BDFs and repeat the manual unlock test |

See [Troubleshooting](docs/TROUBLESHOOTING.md), [Development notes](docs/DEVELOPMENT.md), and [Attribution](docs/ATTRIBUTION.md).
