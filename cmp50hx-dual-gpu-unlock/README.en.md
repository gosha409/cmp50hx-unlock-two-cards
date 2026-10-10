# Dual NVIDIA CMP 50HX (20 GB) compute unlock via UEFI + GRUB

[Полная русская документация](README.md)

An **experimental, reproducible two-GPU UEFI compute-unlock workflow** for the NVIDIA CMP 50HX (TU102, 20 GB). Builds two independently targeted UEFI applications from [xrip/cmp50hx-unlock](https://github.com/xrip/cmp50hx-unlock), chainloads them sequentially from GRUB via `--return-to-grub`, and rearms a one-shot GRUB entry after Linux starts.

**Validated on:** Kali Linux Rolling, `7.1.5+kali-amd64`, NVIDIA/GSP `615.71.09`, dual Xeon E5-2680 v4, Machinist X99-D8 Max, two CMP 50HX boards (PCI ID `10de:1e09`, subsystem `10de:1554`). **No VBIOS flash or NVIDIA kernel driver replacement.**

| OpenCL clpeak FP32 | GPU 0 | GPU 1 |
|---|---:|---:|
| Locked | 0.427 TFLOPS | 0.427 TFLOPS |
| Unlocked | **13.5 TFLOPS** | **13.5 TFLOPS** |

The combined number is not the throughput of one distributed model. VRAM remains two separate 20 GB pools. PCIe remained **Gen1 x4 + Gen1 x16**: this project does not implement PCIe Gen2, NVLink, ReBAR, or memory pooling. Cold boot after full power removal and moving cards to other slots remain untested.

**Usage:** see [Russian installation instructions](docs/INSTALL_RU.md), [results](docs/RESULTS.md), [attribution and licensing](docs/ATTRIBUTION.md). The build script generates files only; installation requires separate, explicit administrative steps. **EFI unlock can hang hardware; recovery may require a full power cycle.**

**Credit:** The firmware exploit/UEFI unlock is the work of [xrip/cmp50hx-unlock](https://github.com/xrip/cmp50hx-unlock). This repository documents the independently tested two-GPU orchestration. Neither upstream EFI blobs nor pre-built modified binaries are redistributed here.
