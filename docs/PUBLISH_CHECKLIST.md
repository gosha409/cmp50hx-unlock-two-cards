# Публикация на GitHub: чек-лист

## 1. Что заполнить до публикации

- [ ] Название репозитория, например `cmp50hx-dual-gpu-unlock`.
- [ ] Указать авторство upstream и ссылки на `xrip/cmp50hx-unlock` в README.
- [ ] Вставить точный commit SHA upstream из `git -C /root/cmp50hx-unlock-src rev-parse HEAD` (в оригинальной стенограмме SHA не указан).
- [ ] Уточнить, какие CPU/GPU/Kernel/Driver версии проверены, а какие не проверены.
- [ ] Не объявлять PCIe Gen2, x16 на обеих GPU, P2P/NVLink или cold boot проверенными: таких результатов нет.
- [ ] Не публиковать GPU UUID, hostname, серийные номера, внутренние IP, личные директории, дампы VBIOS или UEFI variables без необходимости.
- [ ] Не выкладывать EFI firmware binaries и чужие blobs без отдельной проверки лицензий, исходников и права на распространение.
- [ ] Определить собственную лицензию для **оригинальных** документации и вспомогательных скриптов. Она не может переопределить upstream-лицензии.
- [ ] Если добавляете ELF/EFI файлы, обеспечить соответствующую публикацию исходников и copyright-уведомлений по лицензиям всех включённых компонентов.
- [ ] Проверить, что `scripts/build-dual.sh` воспроизводит сборку на чистой копии **того же** upstream commit. При другом upstream сборка может остановиться на проверке исходных якорей.

## 2. Создание репозитория

Создайте **пустой** репозиторий в интерфейсе GitHub, например `cmp50hx-dual-gpu-unlock`. Затем локально из каталога этого пакета:

```bash
git init
git branch -M main
git add .
git status --short
git commit -m "Document dual CMP 50HX UEFI compute unlock on Kali"
git remote add origin https://github.com/YOUR_USERNAME/cmp50hx-dual-gpu-unlock.git
git push -u origin main
```

Используйте SSH URL вместо HTTPS, если настроена SSH-авторизация GitHub. Перед `git add .` перечитайте `.gitignore` и проверьте `git status --short`.

## 3. Рекомендуемое описание GitHub

**Description:**

```text
Dual NVIDIA CMP 50HX UEFI compute unlock on Kali Linux: two ordinal-selected EFI apps, sequential GRUB chainloading, reproducible scripts, FP32 0.427 to 13.5 TFLOPS per GPU.
```

**Topics:**

```text
nvidia cmp50hx gpu uefi grub linux kali-linux turing multi-gpu opencl
```

## 4. Как предоставить подтверждения без чувствительных данных

Добавьте `docs/RESULTS.md` и при желании отредактированный фрагмент OpenCL `clpeak`, где видны обе карты и их FP32-показатели. GPU UUID и уникальные идентификаторы железа публиковать не обязательно. Логи EFI публикуйте лишь после проверки на приватные сведения.

## 5. Куда ещё полезно отправить результаты

Откройте обсуждение или issue в [xrip/cmp50hx-unlock](https://github.com/xrip/cmp50hx-unlock) со ссылкой на свой репозиторий. Разграничьте авторство: автор upstream реализовал сам unlock, ваше практическое дополнение — подтверждённый сценарий двух GPU, ordinal-based выбор и связка GRUB/systemd.
