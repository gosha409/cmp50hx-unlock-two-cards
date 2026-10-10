# Troubleshooting / диагностика

## Обе CMP остались на 427 GFLOPS после reboot

Это означает, что обе карты по `clpeak` демонстрируют ограниченную FP32-производительность. Не следует приписывать проблему автоматически одному компоненту. Проверьте:

```bash
sudo efibootmgr | grep -E 'BootCurrent|BootOrder|BootNext'
sudo grub-editenv /boot/grub/grubenv list
sudo systemctl status cmp50-auto-boot.service --no-pager
sudo grep -A26 "menuentry 'CMP 50HX AUTO" /boot/grub/grub.cfg
sudo grep -aEi 'UNLOCKED|failed|not found|chainload|WPR2' \
  /boot/efi/50hx_log.txt | tail -60
```

`next_entry=cmp50-auto` **после** загрузки означает, что `systemd` выставил выбор для **следующей** загрузки; это не доказывает выполнение EFI во время **текущей** загрузки. Откройте GRUB вручную и проверьте наличие пункта `CMP 50HX AUTO - BOTH GPUs`. В первом меню не выбирайте обычную Kali, если тестируете однократный запуск.

## Только один GPU даёт 13.5 TFLOPS

Вероятно, выполнилась одна из двух разблокировок. Проверьте существование двух EFI-файлов, консоль GRUB, второй вызов `chainloader` и то, что обе версии собраны из одинаковой pristine-версии исходника. Не перепрошивайте VBIOS по одному этому признаку. Внимание: последний EFI может перезаписать `/boot/efi/50hx_log.txt`, поэтому один `UNLOCKED` в нём не доказывает работу обоих.

## Ошибка линковки `elf_x86_64_efi.lds` not found

На проверенной Kali `gnu-efi` использовал `/usr/lib/x86_64-linux-gnu`, а upstream `build.sh` рассчитывал на другой путь. Передайте:

```bash
EFI_LIB=/usr/lib/x86_64-linux-gnu bash ./build.sh
```

В пакете `scripts/build-dual.sh` этот параметр задаётся автоматически с возможностью изменить через `EFI_LIB`.

## `objcopy: ...so: file format not recognized`

При выполнении `objcopy` на установленном toolchain требовался `--output-target=efi-app-x86_64` вместо `--target=efi-app-x86_64`. Скрипт изменяет параметр только во временной копии upstream `build.sh`. После сборки проверяется `PE32+` и EFI Subsystem `0x0A`.

## Warnings `CopyMem` discarded const qualifiers

В проверенной системе эти предупреждения не помешали сборке. Они не являются доказательством правильности runtime-кода, но и не объясняют отказ линковки. Зафиксируйте конкретный compiler/toolchain при открытии issue.

## GPU недоступен после эксперимента

EFI влияет на раннюю инициализацию GPU; при зависании может потребоваться **полное выключение питания**, а не soft reboot. Не выполняйте такой эксперимент только по SSH. После восстановления используйте штатный пункт Kali/UEFI и исходный EFI для одиночной CMP.

## PCIe остаётся 2.5 GT/s / x4

Это **не** признак проваленной compute unlock, если `clpeak` показывает 13.5 TFLOPS. На испытании PCIe был Gen1 x4 для GPU0 и Gen1 x16 для GPU1; увеличить скорость и ширину этим набором невозможно.

```bash
for GPU in 03:00.0 84:00.0; do
  echo "=== $GPU ==="
  lspci -s "$GPU" -vv | grep -E 'LnkCap:|LnkSta:'
done
nvidia-smi topo -m
```

`LnkCap` может отражать ограничение PCIe capability самой CMP, поэтому параметры родительских Root Ports, физический слот и райзер надо проверять отдельно. В upstream PCIe Gen2 описан как отдельный OS-side механизм, не выполняемый EFI перед ОС.

## Откат без удаления рабочего EFI

```bash
sudo systemctl disable --now cmp50-auto-boot.service
sudo grub-editenv /boot/grub/grubenv unset next_entry
```

Если обычная Kali запускается — оставьте её первым пунктом. Файлы `/EFI/50HX-AUTO0` и `/EFI/50HX-AUTO1` не нужны для штатной загрузки.

## Как открыть issue

Укажите модель платы, CPU, версию ядра, NVIDIA driver/GSP, VBIOS обеих CMP, PCI device/subsystem ID, GRUB/UEFI, Git commit upstream, SHA-256 двух локальных EFI, clpeak до/после и точный текст ошибки. Удаляйте уникальные GPU UUID, серийники, внутренние IP и личные данные до публикации.
