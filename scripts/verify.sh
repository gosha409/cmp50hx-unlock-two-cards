#!/usr/bin/env bash
# Read-only diagnostic utility. Does not install, patch, or write anything.
set -u
printf '%s\n' '=== OS / KERNEL ==='
uname -srvo
printf '\n%s\n' '=== NVIDIA ==='
if command -v nvidia-smi >/dev/null; then
  nvidia-smi --query-gpu=index,name,pci.bus_id,vbios_version,memory.total --format=csv
  nvidia-smi topo -m
else
  echo 'nvidia-smi not found'
fi
printf '\n%s\n' '=== CMP PCI DEVICES ==='
lspci -Dnn | grep -i '10de:1e09' || true
while read -r BDF; do
  [[ -n "$BDF" ]] || continue
  printf '\n=== %s ===\n' "$BDF"
  lspci -s "$BDF" -vv | grep -E 'LnkCap:|LnkSta:|Subsystem:' || true
done < <(lspci -Dnn | awk '/10de:1e09/ {print $1}')
printf '\n%s\n' '=== EFI BOOT ==='
if command -v efibootmgr >/dev/null; then
  efibootmgr | grep -E '^BootCurrent:|^BootNext:|^BootOrder:' || true
fi
printf '\n%s\n' '=== GRUB ==='
if command -v grub-editenv >/dev/null; then
  grub-editenv /boot/grub/grubenv list || true
fi
printf '\n%s\n' '=== SERVICE ==='
systemctl is-enabled cmp50-auto-boot.service 2>/dev/null || true
printf '\n%s\n' '=== BENCHMARK ==='
if [[ -x /home/kali/clpeak/build/clpeak ]]; then
  echo 'Manual FP32 benchmark: /home/kali/clpeak/build/clpeak --opencl --single-precision-compute'
else
  echo 'clpeak not found at default path; run your local build manually.'
fi
