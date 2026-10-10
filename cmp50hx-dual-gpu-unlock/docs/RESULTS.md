# Результаты стендовых измерений — 10 октября 2026

Платформа: Machinist X99-D8 Max, 2× E5-2680 v4, 2× NVIDIA CMP 50HX 20 GB, Kali Linux Rolling (ядро `7.1.5+kali-amd64`), NVIDIA `615.71.09`, GSP `615.71.09`. Дополнительная GPU — AMD RX 5700 XT.

## Характеристики CMP

| | GPU 0 | GPU 1 |
|---|---|---|
| PCI BDF | `0000:03:00.0` | `0000:84:00.0` |
| Device ID | `10de:1e09` | `10de:1e09` |
| Subsystem ID | `10de:1554` | `10de:1554` |
| VBIOS | `90.02.60.00.1A` | `90.02.60.00.01` |
| Memory | `20480 MiB` | `20480 MiB` |
| OpenCL Compute Units | 56 | 56 |
| Reported frequency in clpeak | 1545 MHz | 1545 MHz |
| PCIe LnkCap | 2.5 GT/s x16 | 2.5 GT/s x16 |
| PCIe LnkSta | **2.5 GT/s x4** | **2.5 GT/s x16** |

## FP32: A/B matrix

| Сценарий / загрузка | GPU 0 | GPU 1 |
|---|---:|---:|
| Изначальный EFI Unlock (только первая карта) | 13.5 TFLOPS | 0.427 TFLOPS |
| Экспериментальная EFI для PCI bus 0x84 | 0.426 TFLOPS | 13.6 TFLOPS |
| Последовательная загрузка двух EFI | 13.5 TFLOPS | 13.6 TFLOPS |
| Динамические ordinal EFI + GRUB | **13.5 TFLOPS** | **13.5 TFLOPS** |

Финальный измеренный результат:

```text
Device 0: NVIDIA CMP 50HX
  float     : 13.5 TFLOPS
  float2    : 13.5 TFLOPS
  float4    : 13.5 TFLOPS
  float8    : 13.4 TFLOPS
  float16   : 13.3 TFLOPS

Device 1: NVIDIA CMP 50HX
  float     : 13.5 TFLOPS
  float2    : 13.5 TFLOPS
  float4    : 13.5 TFLOPS
  float8    : 13.4 TFLOPS
  float16   : 13.3 TFLOPS
```

Команда:

```bash
/home/kali/clpeak/build/clpeak --opencl --single-precision-compute
```

**Точность:** `float2`, `float4`, `float8`, `float16` в данном выводе являются векторными типами с компонентами **FP32**, а не тестом FP16. Отдельный тест FP16 / Tensor Core не проводился. Значения зависят от частот, температур, драйвера и конфигурации теста.

## Подтверждающий лог EFI

```text
[50HX] *** UNLOCKED (SS0=0x88888888 SS1=0x8) ***
```

Журнал `/boot/efi/50hx_log.txt` перезаписывается последним EFI-приложением. Поэтому одного наличия `UNLOCKED` в логе недостаточно для доказательства двойной разблокировки: это подтверждено именно **двумя независимыми результатами clpeak**.

## Boot orchestration

Наблюдались:

```text
BootCurrent: 0001   # загрузка через Kali GRUB
BootOrder: 0001,... # Kali GRUB назначен первым
next_entry=cmp50-auto
cmp50-auto-boot.service: status=0/SUCCESS
```

`inactive (dead)` — нормальное состояние systemd `Type=oneshot` после успешного выполнения.

## Чего пока нельзя утверждать

- Нет измеренной скорости токенов/с для LLM и подтверждения ускорения tensor parallel.
- Нет проверки полного отключения питания и включения с нуля (cold boot).
- Нет проверки переноса карт в другие PCIe-слоты, изменения порядка устройств, третьей карты.
- PCIe остаётся Gen1, одна карта работает на x4; проблема не решена compute unlock.
- Нет долговременного стресс-теста CUDA и замеров энергопотребления.
