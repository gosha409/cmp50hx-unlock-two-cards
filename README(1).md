# Разблокировка двух NVIDIA CMP 50HX (20 GB) через UEFI + GRUB

**[English README](README.md)** · **[Результаты тестов](docs/RESULTS.md)** · **[Диагностика](docs/TROUBLESHOOTING.md)** · **[Авторство и лицензии](docs/ATTRIBUTION.md)**

Практическая инструкция с командами для **двух NVIDIA CMP 50HX**: сборка двух независимых UEFI-разблокировщиков, их последовательный запуск из GRUB, тестирование и настройка автозапуска. **Штатный драйвер NVIDIA и VBIOS не изменяются.**

Основа — [xrip/cmp50hx-unlock](https://github.com/xrip/cmp50hx-unlock). Исходный механизм разблокировки GSP/SEC2, UEFI-код и firmware-компоненты принадлежат upstream и не входят в этот репозиторий. Здесь находятся вспомогательные скрипты, конфигурация загрузки и результаты тестов двух GPU.

> **Предупреждение.** Экспериментальный UEFI-код может зависнуть до загрузки ОС. Для испытания нужны **физический доступ**, возможность полного отключения питания и альтернативная загрузка через GRUB/UEFI. Не запускайте непроверенные EFI на сервере, доступном исключительно через SSH.

## 0. Что удалось получить

| Параметр | GPU 0 | GPU 1 |
|---|---:|---:|
| Устройство | CMP 50HX, 20 GB | CMP 50HX, 20 GB |
| FP32 до разблокировки, `clpeak` | 0,427 TFLOPS | 0,427 TFLOPS |
| FP32 после разблокировки, `clpeak` | **13,5 TFLOPS** | **13,5 TFLOPS** |
| Ускорение FP32 | ~31,6× | ~31,6× |
| PCIe при тестировании | Gen1 x4 | Gen1 x16 |

**Стенд (10.10.2026):** Machinist X99-D8 Max, 2× Xeon E5-2680 v4, Kali Linux Rolling (`7.1.5+kali-amd64`), NVIDIA driver/GSP `615.71.09`, GPU PCI ID `10de:1e09`, subsystem `10de:1554`. Дополнительно установлена AMD RX 5700 XT.

Разблокировка обеих CMP и работа GRUB/systemd проверены на этом стенде. **Не проверены:** холодный старт с полным обесточиванием, перенос карт в другие слоты, другие VBIOS и другие платы, PCIe Gen2, длительная LLM-нагрузка. 40 GB — сумма **двух отдельных** пулов VRAM по 20 GB, не один общий пул. `float16` в показанном выводе `clpeak` — вектор из FP32, **не FP16-бенчмарк**.

## 1. Проверяем сервер

Все следующие команды выполняются **в Kali Linux от root**. На другой Linux-системе названия пакетов и пути к GRUB/ESP могут отличаться.

```bash
sudo -i

# Должен быть UEFI, не Legacy/CSM
[ -d /sys/firmware/efi ] && echo 'UEFI OK' || echo 'ERROR: Legacy boot'

# Должны определяться две CMP 50HX
lspci -Dnn | grep -i '10de:1e09'
nvidia-smi -L
nvidia-smi --query-gpu=index,name,pci.bus_id,vbios_version,memory.total --format=csv

# Проверяем точки монтирования и загрузчик
findmnt /boot/efi
efibootmgr -v | grep -E '^BootCurrent:|^BootOrder:|kali|GRUB'
```

**Продолжайте только если** есть две совместимые CMP, исправно работающий NVIDIA-драйвер, доступный UEFI GRUB и смонтированный EFI System Partition (ESP), обычно `/boot/efi`.

## 2. Сохраняем рабочую конфигурацию

```bash
mkdir -p /root/cmp50hx-backup
cp -a /etc/default/grub /root/cmp50hx-backup/grub-default.before
cp -a /boot/grub/grub.cfg /root/cmp50hx-backup/grub.cfg.before
efibootmgr -v > /root/cmp50hx-backup/efibootmgr.before.txt

# Если уже установлен оригинальный EFI-разблокировщик — сохраняем его
if [ -f /boot/efi/EFI/50HX/50HXUNLK.EFI ]; then
  cp -a /boot/efi/EFI/50HX/50HXUNLK.EFI \
    /root/cmp50hx-backup/50HXUNLK.original.EFI
fi

# При наличии сохраняем старый журнал
if [ -f /boot/efi/50hx_log.txt ]; then
  cp -a /boot/efi/50hx_log.txt /root/cmp50hx-backup/
fi

ls -lh /root/cmp50hx-backup/
```

**Не заменяйте** уже работающий `/boot/efi/EFI/50HX/50HXUNLK.EFI`. Для двух новых EFI ниже используются отдельные каталоги.

## 3. Ставим зависимости и скачиваем исходники

```bash
apt update
apt install -y git build-essential gnu-efi binutils python3 file \
  pciutils efibootmgr cmake clinfo ocl-icd-opencl-dev

cd /root

# Репозиторий уже опубликован; имя каталога задано явно.
# Если пакет скачан ZIP-архивом, распакуйте его содержимое в эту папку.
if [ ! -e /root/cmp50hx-dual-gpu-unlock ]; then
  git clone https://github.com/gosha409/cmp50hx-unlock-two-cards.git \
    cmp50hx-dual-gpu-unlock
fi

# Оригинальный проект, содержащий исходники EFI
# Если каталог уже существует, пропустите эту команду.
if [ ! -d /root/cmp50hx-unlock-src/.git ]; then
  git clone https://github.com/xrip/cmp50hx-unlock.git cmp50hx-unlock-src
fi

# Зафиксируйте ревизию upstream для воспроизводимости
git -C /root/cmp50hx-unlock-src rev-parse HEAD
# Для воспроизводимости можно указать известный SHA upstream:
# export EXPECTED_UPSTREAM_COMMIT=<проверенный_40_символьный_SHA>
```

Если вы загрузили этот проект на сервер вручную, итоговый путь должен быть `/root/cmp50hx-dual-gpu-unlock`, а скрипт — `/root/cmp50hx-dual-gpu-unlock/scripts/build-dual.sh`. Если `git clone` сообщает, что каталог уже существует, не удаляйте его: переходите к следующему шагу.

**Важно:** upstream может изменяться. Скрипт проверяет структуру исходника и останавливается при несовместимых изменениях; принудительно отключать проверки не нужно.

## 4. Собираем два EFI (ничего не устанавливаем)

Сначала проверяем генератор исходников без запуска EFI и доступа к видеокартам:

```bash
cd /root/cmp50hx-dual-gpu-unlock
python3 -m unittest discover -s tests -v
```


```bash
cd /root/cmp50hx-dual-gpu-unlock

bash scripts/build-dual.sh \
  /root/cmp50hx-unlock-src/efi-unlock \
  /root/cmp50hx-dual-gpu-unlock/dist
```

Ожидаемый финал:

```text
BUILD_DUAL_OK (not installed)
```

Проверяем артефакты:

```bash
file dist/50HX-AUTO0.EFI dist/50HX-AUTO1.EFI
objdump -p dist/50HX-AUTO0.EFI | grep -i Subsystem
objdump -p dist/50HX-AUTO1.EFI | grep -i Subsystem
sha256sum dist/50HX-AUTO*.EFI
ls -lh dist/
```

Оба файла должны быть **PE32+ EFI Application**, подсистема `0x0A`. Скрипт локально исправляет путь `gnu-efi` на Kali и параметр `objcopy --output-target`, не редактируя исходный upstream. Не запускайте следующую часть, если сборка не завершилась успешно.

**Как устроен выбор:** `AUTO0` разблокирует первую обнаруженную совместимую CMP, `AUTO1` — вторую. В отличие от первоначального теста с PCI-шинами `03` и `84`, **адреса не зашиты в EFI**, однако переносимость после перестановки карт не подтверждена.

## 5. Копируем EFI в отдельные каталоги загрузочного раздела

```bash
# Контроль: это действительно EFI System Partition
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

Сравните контрольные суммы для соответствующих пар файлов. Старый EFI в `/EFI/50HX/` остаётся нетронутым.

## 6. Добавляем в GRUB отдельный тестовый пункт

```bash
cd /root/cmp50hx-dual-gpu-unlock
install -m 0755 grub/42_cmp50_auto /etc/grub.d/42_cmp50_auto
nano /etc/default/grub
```

В `/etc/default/grub` установите **по одному** экземпляру каждого параметра:

```ini
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=10
```

`GRUB_DEFAULT=0` подходит **только если** первый пункт стандартного меню — обычная Kali. На иной конфигурации укажите именно штатную Kali. **Никогда не ставьте `GRUB_DEFAULT=cmp50-auto`**: из-за повторного открытия GRUB получится риск циклического запуска.

```bash
update-grub
grub-script-check /boot/grub/grub.cfg
grep -A25 "menuentry 'CMP 50HX AUTO" /boot/grub/grub.cfg
```

Должен появиться пункт **CMP 50HX AUTO - BOTH GPUs**, где последовательно вызываются два EFI с `--return-to-grub`, затем открывается стандартное меню Kali.

## 7. Проводим ручной тест (обязательно до автозапуска)

```bash
# Отключаем возможный автоматический выбор пункта
systemctl disable --now cmp50-auto-boot.service 2>/dev/null || true
grub-editenv /boot/grub/grubenv unset next_entry

# Смотрим фактический номер загрузки Kali GRUB
efibootmgr -v | grep -E '^Boot[0-9A-Fa-f]{4}\*.*(kali|Kali|GRUB)'
```

В примере стенда Kali GRUB — `Boot0001`. **Подставьте свой номер вместо `0001`:**

```bash
KALI_BOOT_ID=0001

efibootmgr -n "$KALI_BOOT_ID"
efibootmgr | grep -E '^BootNext:|^BootOrder:'
sync
reboot
```

В первом меню GRUB **вручную** выберите `CMP 50HX AUTO - BOTH GPUs`. После выполнения обеих EFI-разблокировок откроется стандартное меню GRUB — там выберите **обычную Kali**. Не запускайте тестовый пункт повторно.

### Проверяем разблокировку

Если `clpeak` ещё нет, соберите его:

```bash
cd /root
if [ ! -d /root/clpeak/.git ]; then
  git clone --recursive https://github.com/krrishnarraj/clpeak.git /root/clpeak
fi
git -C /root/clpeak submodule update --init --recursive
cmake -S /root/clpeak -B /root/clpeak/build
cmake --build /root/clpeak/build -j4
```

Теперь запускаем проверку FP32:

```bash
/root/clpeak/build/clpeak --opencl --single-precision-compute

# Проверяем ошибки NVIDIA
journalctl -k -b --no-pager | grep -E 'NVRM: Xid|GPU has fallen off' || true

# Дополнительная диагностика
bash /root/cmp50hx-dual-gpu-unlock/scripts/verify.sh
```

**Ожидаем на стенде:** около `13.5 TFLOPS` для **каждой** CMP. Если обе показывают ~`0.427 TFLOPS` или только одна разблокирована, **не включайте systemd-автоматизацию**; см. [диагностику](docs/TROUBLESHOOTING.md). `50hx_log.txt` может перезаписываться вторым EFI, поэтому результат обеих карт в `clpeak` — основная проверка.

## 8. Включаем автоматическую разблокировку

**Выполнять только после успешного ручного теста из шага 7.** Служба systemd выставляет `grub-reboot cmp50-auto` на **следующую** загрузку. После входа в Kali это задание будет выставлено снова.

```bash
cd /root/cmp50hx-dual-gpu-unlock

install -m 0644 systemd/cmp50-auto-boot.service \
  /etc/systemd/system/cmp50-auto-boot.service

systemctl daemon-reload
systemctl enable --now cmp50-auto-boot.service
systemctl status cmp50-auto-boot.service --no-pager
grub-editenv /boot/grub/grubenv list
```

Нормальный результат:

```text
ExecStart=/usr/sbin/grub-reboot cmp50-auto (status=0/SUCCESS)
Active: inactive (dead)
next_entry=cmp50-auto
```

`inactive (dead)` — нормальное состояние завершённой **oneshot**-службы. `next_entry` после загрузки — состояние **следующей**, не текущей загрузки, и само по себе не доказывает разблокировку GPU.

### Делаем Kali GRUB первой UEFI-записью

```bash
efibootmgr -v
```

Найдите ID Kali, например `0001`, и сверяйте его с выводом **на вашей машине**. Если Kali не первая, можно переставить её первой **с сохранением остальных записей**:

```bash
KALI_BOOT_ID=0001    # ЗАМЕНИТЕ на свой BootXXXX с Kali GRUB

efibootmgr -v | grep -E "^Boot${KALI_BOOT_ID}[*]" || {
  echo 'Неверный Boot ID; остановка'; exit 1;
}

CURRENT_ORDER=$(efibootmgr | sed -n 's/^BootOrder: //p')
REST=$(printf '%s\n' "$CURRENT_ORDER" | tr ',' '\n' | \
  grep -v -x "$KALI_BOOT_ID" | paste -sd, -)

efibootmgr -o "${KALI_BOOT_ID},${REST}"
efibootmgr | grep -E '^BootOrder:|^BootNext:'
```

Проверьте, что первая запись теперь **Kali GRUB**, а не Windows Boot Manager. После этого:

```bash
sync
reboot
```

В **первом** меню GRUB ничего не нажимайте: должен автоматически выбраться `CMP 50HX AUTO - BOTH GPUs`. Во **втором** меню загрузите обычную Kali (если стандартный пункт выбран по умолчанию, это произойдёт по тайм-ауту). После загрузки снова запустите `clpeak`.

## 9. Проверяем после каждой значимой смены конфигурации

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

PCI-адреса в цикле выше — **только пример** из нашего стенда; после перестановки карт найдите новые через `lspci -Dnn`. Этот проект **не** снимает ограничение PCIe Gen1, не даёт NVLink и не объединяет VRAM. Текущие измерения скорости PCIe — Gen1 x4 и Gen1 x16.

## 10. Как отключить и откатить

Чтобы **отключить автоматическую разблокировку для следующей загрузки**, не удаляя рабочие EFI-файлы:

```bash
systemctl disable --now cmp50-auto-boot.service
grub-editenv /boot/grub/grubenv unset next_entry
grub-editenv /boot/grub/grubenv list
```

Чтобы дополнительно **удалить тестовый пункт GRUB**:

```bash
rm -f /etc/grub.d/42_cmp50_auto
update-grub
grub-script-check /boot/grub/grub.cfg
```

При необходимости вернуть прежний `/etc/default/grub` используйте сохранённый файл (только если это действительно ваш backup):

```bash
cp -a /root/cmp50hx-backup/grub-default.before /etc/default/grub
update-grub
```

Если при старте зависает UEFI, обычные Linux-команды уже недоступны: используйте локальную консоль, альтернативный пункт загрузки и при необходимости **полное выключение питания**. Экспериментальные файлы `EFI/50HX-AUTO0` и `EFI/50HX-AUTO1` можно удалить позже, когда загрузка стабилизирована; **не удаляйте исходный `/EFI/50HX/`**.

## Куда смотреть при ошибках

| Симптом | Действие |
|---|---|
| `elf_x86_64_efi.lds: No such file` | Пакет `gnu-efi`, путь `EFI_LIB=/usr/lib/x86_64-linux-gnu`; наш build-скрипт задаёт его автоматически |
| `objcopy: file format not recognized` | Использовать `--output-target=efi-app-x86_64`; наш build-скрипт правит временную копию `build.sh` |
| После reboot ~427 GFLOPS на обеих | Проверить, запускался ли пункт `cmp50-auto`; выбрать вручную и смотреть EFI-лог |
| Разблокирована одна карта | Проверить `AUTO0`, `AUTO1`, обе команды chainloader и результат `clpeak` |
| systemd `inactive (dead)` | Для oneshot это ожидаемо, если `status=0/SUCCESS` |
| Изменились PCI BDF после перестановки | Проверить новый порядок поиска устройств и повторить ручной тест |

Полная диагностика: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md). История эксперимента: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Права и авторство

Используются исходники [xrip/cmp50hx-unlock](https://github.com/xrip/cmp50hx-unlock). Этот репозиторий не включает upstream firmware blobs, дампы VBIOS и готовые EFI. Перед публикацией производных бинарников проверьте лицензии upstream и компонентов firmware. Подробности — [docs/ATTRIBUTION.md](docs/ATTRIBUTION.md).
