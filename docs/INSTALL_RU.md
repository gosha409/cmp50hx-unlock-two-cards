# Воспроизводимая установка — две CMP 50HX, Kali Linux

## 0. Область применимости и риски

Описанная последовательность **проверена на одном стенде 10.10.2026**: Kali `7.1.5+kali-amd64`, NVIDIA `615.71.09`, 2× CMP 50HX `10de:1e09` по 20 GB, GRUB/UEFI. На других прошивках и драйверах работоспособность не гарантируется.

**Нужно:** root-доступ; физический доступ к серверу, клавиатура/консоль; возможность полного отключения питания; резервная загрузка; тестирование прежде постоянной автоматизации. **Нельзя** выполнять процедуру в расчёте только на удалённый SSH без возможности вернуть машину после зависания EFI.

Важные особенности: `grub-reboot` — однократный выбор, но его заново выставляет systemd; постоянно назначать `GRUB_DEFAULT=cmp50-auto` нельзя, поскольку пункт в конце вызывает ещё один GRUB-конфиг.

## 1. Сохраняем текущие настройки

```bash
sudo -i
mkdir -p /root/cmp50hx-backup
cp -a /etc/default/grub /root/cmp50hx-backup/default-grub.before-dual
cp -a /boot/grub/grub.cfg /root/cmp50hx-backup/grub.cfg.before-dual
cp -a /boot/efi/50hx_log.txt /root/cmp50hx-backup/ 2>/dev/null || true
efibootmgr -v > /root/cmp50hx-backup/efibootmgr.before-dual.txt
findmnt /boot/efi
```

Если ранее уже был установлен работающий EFI, сохраните **его же** отдельно до каких-либо изменений:

```bash
if [ -f /boot/efi/EFI/50HX/50HXUNLK.EFI ]; then
  cp -a /boot/efi/EFI/50HX/50HXUNLK.EFI \
    /root/cmp50hx-backup/50HXUNLK.original.EFI
  sha256sum /root/cmp50hx-backup/50HXUNLK.original.EFI
else
  echo "No existing EFI unlocker to back up"
fi
```

В тестовой системе hash исходного рабочего EFI начинался с `4d42434b...`, однако он не является универсальным эталоном: сравнивайте с **собственной** сохранённой копией.

## 2. Получаем upstream и зависимости

```bash
sudo apt update
sudo apt install -y git build-essential gnu-efi binutils python3 file cmake clinfo ocl-icd-opencl-dev
cd /root
if [ ! -e /root/cmp50hx-dual-gpu-unlock ]; then
  git clone https://github.com/gosha409/cmp50hx-unlock-two-cards.git /root/cmp50hx-dual-gpu-unlock
fi
if [ ! -d /root/cmp50hx-unlock-src/.git ]; then
  git clone https://github.com/xrip/cmp50hx-unlock.git cmp50hx-unlock-src
fi
```

В тестовой системе код проекта был клонирован 10.10.2026; точный commit hash в журнале сессии не сохранён. Для воспроизводимости публикации фиксируйте:

```bash
git -C /root/cmp50hx-unlock-src rev-parse HEAD
```

После изменения upstream структура `unlock50x_v1.c` может отличаться. Скрипт сборки в этом наборе **откажется продолжать работу**, если не найдёт ожидаемые участки кода. Не обходите эти проверки без изучения отличий.

## 3. Собираем два независимых EFI

Команды из каталога **этого** репозитория (после `cd /root/cmp50hx-dual-gpu-unlock`):

```bash
cd /root/cmp50hx-dual-gpu-unlock
python3 -m unittest discover -s tests -v
bash scripts/build-dual.sh \
  /root/cmp50hx-unlock-src/efi-unlock \
  ./dist
```

Скрипт:

- делает временную копию upstream `efi-unlock`;
- берёт чистый `unlock50x_v1.c` из `.orig` или Git HEAD;
- строит две версии C: **ordinal 0** и **ordinal 1**;
- использует `/usr/lib/x86_64-linux-gnu` для Kali GNU EFI;
- меняет `--target=efi-app-x86_64` на `--output-target=efi-app-x86_64` в **временной** копии `build.sh`;
- проверяет PE32+ / EFI subsystem `0x0A`;
- записывает `dist/50HX-AUTO0.EFI`, `dist/50HX-AUTO1.EFI`, build logs и `upstream-commit.txt` (при доступности Git).

**Не устанавливает EFI и не изменяет работающую систему.**

Ожидаемый финал: `BUILD_DUAL_OK (not installed)`.

Вручную проверить:

```bash
file dist/50HX-AUTO0.EFI dist/50HX-AUTO1.EFI
objdump -p dist/50HX-AUTO0.EFI | grep -i 'Subsystem'
objdump -p dist/50HX-AUTO1.EFI | grep -i 'Subsystem'
sha256sum dist/50HX-AUTO*.EFI
```

Не копируйте чужие опубликованные SHA как контрольную сумму для своих сборок: хеш зависит от версии исходника и компиляции.

## 4. Размещаем в ESP, не трогая исходную EFI

```bash
sudo mkdir -p /boot/efi/EFI/50HX-AUTO0 /boot/efi/EFI/50HX-AUTO1
sudo install -m 0644 dist/50HX-AUTO0.EFI \
  /boot/efi/EFI/50HX-AUTO0/50HXUNLK.EFI
sudo install -m 0644 dist/50HX-AUTO1.EFI \
  /boot/efi/EFI/50HX-AUTO1/50HXUNLK.EFI
sha256sum /boot/efi/EFI/50HX-AUTO{0,1}/50HXUNLK.EFI
```

## 5. Создаём тестовый пункт GRUB

```bash
sudo install -m 0755 grub/42_cmp50_auto /etc/grub.d/42_cmp50_auto
sudo nano /etc/default/grub
```

Убедитесь, что параметры установлены **ровно один раз** и обычная Kali остаётся пунктом по умолчанию:

```ini
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=10
```

Если на вашей системе первым пунктом GRUB является не обычная Kali, скорректируйте `GRUB_DEFAULT` на её идентификатор. **Не используйте `GRUB_DEFAULT=cmp50-auto`**.

```bash
sudo update-grub
sudo grub-script-check /boot/grub/grub.cfg
grep -F "CMP 50HX AUTO - BOTH GPUs" /boot/grub/grub.cfg
```

В меню новый пункт запускает оба EFI по очереди с `--return-to-grub`, а затем выполняет `configfile $prefix/grub.cfg`, чтобы вернуться в обычное загрузочное меню.

## 6. Ручной тест (до автозапуска)

Сначала отключите автоматическую службу, если ранее создавали её:

```bash
sudo systemctl disable --now cmp50-auto-boot.service 2>/dev/null || true
sudo grub-editenv /boot/grub/grubenv unset next_entry
```

Выполните `efibootmgr -v` и определите запись **Kali GRUB**, которая на нашем стенде была `0001` (на другой системе может быть другой номер). Укажите её один раз через BootNext:

```bash
sudo efibootmgr -n 0001  # только если Kali GRUB действительно Boot0001
sudo sync
sudo reboot
```

В GRUB вручную выберите `CMP 50HX AUTO - BOTH GPUs`. Дождитесь возврата в меню, затем выберите **обычную Kali**. Не выбирайте экспериментальный пункт второй раз.

После старта (если `clpeak` ещё нет):

```bash
cd /root
if [ ! -d /root/clpeak/.git ]; then
  git clone --recursive https://github.com/krrishnarraj/clpeak.git /root/clpeak
fi
git -C /root/clpeak submodule update --init --recursive
cmake -S /root/clpeak -B /root/clpeak/build
cmake --build /root/clpeak/build -j4

nvidia-smi -L
/root/clpeak/build/clpeak --opencl --single-precision-compute
```

Ориентир по результатам нашего теста: по **13.5 TFLOPS FP32** на обоих CMP. Убедитесь, что в `dmesg` нет новых `NVRM: Xid`:

```bash
journalctl -k -b --no-pager | grep 'NVRM: Xid' || true
```

Если результат неудовлетворительный, **не включайте постоянный запуск**, пользуйтесь обычной Kali и изучите [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## 7. Автоматизация — только после успешного ручного теста

```bash
sudo install -m 0644 systemd/cmp50-auto-boot.service \
  /etc/systemd/system/cmp50-auto-boot.service
sudo systemctl daemon-reload
sudo systemctl enable --now cmp50-auto-boot.service
sudo systemctl status cmp50-auto-boot.service --no-pager
sudo grub-editenv /boot/grub/grubenv list
```

Ожидается `next_entry=cmp50-auto`, а сервис будет `inactive (dead)` после `status=0/SUCCESS` — это нормально для `Type=oneshot`.

Убедитесь, что **Kali GRUB** первая в `BootOrder`:

```bash
sudo efibootmgr
```

Для тестового стенда была установлена последовательность:

```text
BootOrder: 0001,0000,0005,0003,0004,0002,0006
```

**Не копируйте BootOrder как универсальную команду.** Если он отличается, сохраните текущие значения, определите правильный ID Kali и измените порядок только после проверки записей.

Перезагрузитесь, **не нажимая клавиши в первом меню GRUB**. После разблокировки будет обычное меню с Kali. Снова проверьте обе карты через `clpeak`.

### Почему не просто GRUB_DEFAULT=cmp50-auto

После выполнения обоих EFI пункт повторно открывает GRUB (`configfile $prefix/grub.cfg`); при постоянном выборе самого себя может возникнуть цикл. Однократный `grub-reboot` выбирает цепочку один раз, затем штатный пункт Kali; systemd повторно подготавливает `next_entry` после успешного старта ОС. Такой подход **не является аппаратным watchdog** и не заменяет резервную загрузку.

## 8. Отключение и откат

При необходимости отменить следующую разблокировку, **не удаляя файлов**:

```bash
sudo systemctl disable --now cmp50-auto-boot.service
sudo grub-editenv /boot/grub/grubenv unset next_entry
```

После восстановления штатной работы можно убрать пункт GRUB:

```bash
sudo rm -f /etc/grub.d/42_cmp50_auto
sudo update-grub
```

Удалять экспериментальные каталоги ESP необязательно; если удаляете, **только свои AUTO-каталоги**, а не ранее работавший `/EFI/50HX`:

```bash
sudo rm -rf /boot/efi/EFI/50HX-AUTO0 /boot/efi/EFI/50HX-AUTO1
```

При неудачной настройке UEFI восстановите `BootOrder` из `/root/cmp50hx-backup/efibootmgr.before-dual.txt`. Отдельные `Boot0005` / `Boot0006` могут служить аварийными ручными записями, если установлены в вашей системе. Для полностью чистого отката состояния самой GPU предпочтителен cold power cycle.

## 9. Примечание о публикации

Не выкладывайте содержимое папки upstream, чужие EFI-бинарники, firmware blobs и приватные логи без проверки лицензирования. Публикуйте **эту документацию, оригинальную обвязку и результаты**, указывая источник upstream и commit SHA.
