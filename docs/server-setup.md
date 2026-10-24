# Настройка devops-vm на macOS — практические работы № 5–6

Это новая виртуальная машина на Mac с Apple Silicon (M3). Прежняя работа на Windows, включая Nginx и Docker из практических работ № 6–7, сохранена в [архивном описании](server-setup-windows-archive.md). Команды и результаты из него **не относятся** к нынешней VM.

## 1. Виртуальная машина

| Параметр | Текущее значение |
| --- | --- |
| Гипервизор | Oracle VirtualBox 7.2.22 для Apple Silicon |
| Имя | `devops-vm` |
| Гостевая ОС | Ubuntu Server 24.04.5 LTS, ARM64 (aarch64), без GUI |
| Ядро на дату проверки | `6.8.0-147-generic` |
| Ресурсы | 2048 МБ RAM, 2 CPU, динамический VDI 25 ГБ |
| Прошивка и диск | EFI, VirtioSCSI, `/boot/efi` FAT32 и корень `/` ext4 |
| Имя узла | `devops-vm`; FQDN `devops-vm.devops.local` |
| Часовой пояс гостевой ОС | `Etc/UTC` |

После смены Host-only IP потребуется обновить `/etc/hosts` на Mac. Адрес VM можно проверить командой `ip -brief -4 address`.

## 2. Сеть и доступ с Mac

| Интерфейс VM | Режим VirtualBox | Адрес на дату проверки | Назначение |
| --- | --- | --- | --- |
| `enp0s8` | NAT | `10.0.2.15/24` | Доступ в интернет и проброс SSH |
| `enp0s9` | Host-only Network `HostNetwork` | `192.168.56.2/24` | Прямой доступ с Mac |
| `lo` | Loopback | `127.0.0.1/8` | Локальные службы |

Адрес хоста в сети Host-only: `192.168.56.1`. В VirtualBox настроено правило NAT `ssh`: TCP `127.0.0.1:2222` на Mac → порт `2222` гостя; адрес гостя в правиле пустой. До усиления SSH правило направляло на порт гостя 22.

В `/etc/hosts` macOS добавлено:

```text
192.168.56.2 devops.local
```

`devops.local` — локальная запись hosts, а не отдельный DNS-сервер. `ping -c 2 devops.local` и `ssh -p 2222 devops@devops.local` проверены с Mac. Альтернативный путь: `ssh devops` через NAT-проброс.

На Mac настроен SSH-алиас в `~/.ssh/config`:

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
    AddKeysToAgent yes
    UseKeychain yes
```

Приватный ключ `~/.ssh/devops_vm` остаётся **только на Mac**. В репозитории нет ни приватного ключа, ни паролей. Публичный ключ установлен в `/home/devops/.ssh/authorized_keys` на VM; права каталога 700, файла 600. Ключ Mac добавлен в ssh-agent/Keychain. Отпечаток публичного **ключа сервера** Ed25519: `SHA256:fLMhaqiXranYtXh1QGNf48YmPwbsuEQWjYtc/omGzwc`. Он был сверен с консолью VM до первого SSH-подключения.

## 3. Учётные записи

| Пользователь | UID | Группы | Назначение |
| --- | --- | --- | --- |
| `student` | 1000 | `student adm cdrom sudo dip plugdev lxd` | Первоначальная учётная запись; после усиления SSH вход запрещён правилом `AllowUsers` |
| `devops` | 1001 | `devops sudo users` | Работа по SSH с ключом; пароль используется для `sudo` и входа через консоль |
| `root` | 0 | `root` | Прямой вход по SSH запрещён |

## 4. SSH

Основной файл `/etc/ssh/sshd_config` предварительно скопирован в `/etc/ssh/sshd_config.backup`. В `/etc/ssh/sshd_config.d/50-cloud-init.conf` закомментировано старое `PasswordAuthentication yes`: в OpenSSH ранее прочитанное значение имеет приоритет. Действующие ограничения записаны в `/etc/ssh/sshd_config.d/99-hardening.conf`:

```text
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

`ssh.socket` отключён, `ssh.service` включён и активен. Демон слушает IPv4 и IPv6 на порту 2222. Проверки синтаксиса `sudo sshd -t` и действующих значений `sudo sshd -T` выполнены. Новое подключение по ключу успешно; вход root и парольный вход отклоняются. После усиления сервер предлагает только метод `publickey`.

При восстановлении настройки сначала проверить синтаксис, затем перезапустить службу и открыть **вторую** сессию, сохранив первую до успешного входа:

```bash
sudo sshd -t
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh.service
sudo ss -tlnp | grep sshd
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers) '
```

Если восстановлен снимок до усиления SSH, сначала использовать гостевой порт 22 в NAT-пробросе. После настройки `Port 2222` поменять проброс на гостевой 2222.

## 5. Межсетевой экран

UFW активен и включён на запуск системы. Политики: `deny (incoming)`, `allow (outgoing)`, `disabled (routed)`; ведётся журнал `medium`.

| Порт | Правило IPv4 и IPv6 | Комментарий |
| --- | --- | --- |
| 2222/tcp | `LIMIT IN` | SSH rate-limited |
| 80/tcp | `ALLOW IN` | HTTP |
| 443/tcp | `ALLOW IN` | HTTPS |

Порты 80 и 443 разрешены для веб-сервера. Правило SSH было создано **до** включения UFW. После активации проверено новое SSH-подключение. Запрос с Mac к `192.168.56.2:8080` заблокирован; `/var/log/ufw.log` содержит `SRC=192.168.56.1`, `DST=192.168.56.2`, `PROTO=TCP`, `DPT=8080`.

Проверить состояние:

```bash
sudo ufw status verbose
sudo ufw status numbered
sudo grep 'UFW BLOCK' /var/log/ufw.log | tail -5
```

При повторном создании правил использовать `sudo ufw limit 2222/tcp comment 'SSH rate-limited'` до `sudo ufw enable`; правило `ufw allow ssh` откроет стандартный порт 22 и здесь не подходит.

## 6. Снимки VirtualBox

| Снимок | Создан 24.10.2026 | Сохранённое состояние |
| --- | --- | --- |
| `01-clean-install` | 14:22 | Установленная и обновлённая ОС, пользователь student, первоначальный SSH на порту 22 |
| `02-keys-configured` | 14:31 | Создан devops, добавлен публичный ключ, вход по ключу проверен |
| `03-ssh-hardened` | 14:42 | SSH на порту 2222, запрет root и пароля, новые подключения проверены |
| `04-nginx-https` | 15:36 | Nginx, перенаправление HTTP на HTTPS, сертификат; до доставки страниц из Git |

UUID снимков текущей VM: `01-clean-install` — `48c02b8b-3260-4e67-ae05-ec5979e2aa3d`; `02-keys-configured` — `44fb20b2-a0c3-4c84-8af9-146f6d29709c`; `03-ssh-hardened` — `e714da24-c016-4ed7-b165-3675718c578b`; `04-nginx-https` — `b560a10d-e3e7-43f9-8988-3202415e18bc`. Они находятся только на этом Mac, в каталоге VirtualBox VM, а не в Git.

Снимок `04-nginx-https` создан при выключенной VM, потому что живое сохранение памяти VirtualBox не завершилось; отменённая попытка снимка не изменила VM. Снимок включает UFW и FQDN. Откат к `03-ssh-hardened` потеряет их и веб-сервер. После любого отката проверить NAT-проброс и Host-only IP перед повторным SSH-входом.

## 7. Аудит для практической работы № 5

В `scripts/audit.sh` есть режим `--pr5`: он проверяет запрет root и пароля, нестандартный SSH-порт, `MaxAuthTries 3`, активность UFW и политику `deny incoming`. Список локальных пользователей выводится отдельно. На нынешней VM проверено: 6 OK, 0 FAIL и код выхода 0.

```bash
# На Mac из корня репозитория:
scp scripts/audit.sh devops:~/audit.sh
# В SSH-сессии devops на VM:
bash ~/audit.sh --pr5
echo $?
```

Отрицательная проверка также выполнена на нынешней VM: после временного изменения `MaxAuthTries` с 3 на 10 аудит показал 5 OK, 1 FAIL и код 1. Исходный файл автоматически восстановлен; `sudo sshd -T` снова показывает `maxauthtries 3`. Перезапуск SSH не понадобился: `sshd -T` читает конфигурацию с диска. Перед любым будущим перезапуском службы выполнить `sudo sshd -t`. Полный режим `--all` (он же режим по умолчанию) сохранён для прежних работ № 6–7 и на нынешней VM закономерно обнаружит отсутствие Nginx и Docker.

## 8. Веб-сервер

На текущей VM устанавливаются пакеты `nginx` и `rsync` из репозиториев Ubuntu. Воспроизводимый сценарий начальной настройки — `scripts/setup-pr6.sh`; актуальная конфигурация ресурса — `config/nginx/devops-site.conf`. Сценарий копирует её в `/etc/nginx/sites-available/devops-site` и включает ссылкой `/etc/nginx/sites-enabled/devops-site`. Стандартный ресурс отключён удалением ссылки `sites-enabled/default`, исходный файл в `sites-available` сохраняется. Конфигурацию применять только после `sudo nginx -t`, командой `sudo systemctl reload nginx`.

Порт 80 отвечает постоянным перенаправлением `301` на `https://devops.local`; порт 443 обслуживает TLS 1.2 и 1.3. Заголовок HSTS намеренно не задан: сертификат самоподписанный. Запросы к несуществующим путям возвращают `404` и содержимое `404.html`. Журналы ресурса: `/var/log/nginx/devops-site.access.log` и `/var/log/nginx/devops-site.error.log`.

Статические файлы расположены в `/var/www/devops-site/`, владелец и группа — `devops:devops`, права каталогов `755`, файлов `644`. Рабочие процессы Nginx (`www-data`) могут читать файлы, но не изменять их. Каталог на Mac — `site/` в этом репозитории. Сценарий `scripts/deploy.sh [--dry-run]` доставляет его содержимое через `rsync --delete --chmod=D755,F644`; перед первым запуском с новой целью использовать `--dry-run`. Сценарий требует чистую рабочую копию Git и `site/index.html`, после доставки проверяет HTTPS с доверенным сертификатом и выводит короткий хеш коммита. Один запуск открывает не более одного SSH-соединения. Алиас `devops` определён в `~/.ssh/config` Mac.

Сертификат `/etc/ssl/certs/devops.crt` принадлежит `root:root` и имеет права `644`; закрытый ключ `/etc/ssl/private/devops.key` принадлежит `root:root` и имеет права `600`. Сертификат действует 365 дней со дня выпуска, содержит SAN `DNS:devops.local` и создаётся командой:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj '/CN=devops.local' \
  -addext 'subjectAltName=DNS:devops.local'
```

Закрытый ключ никогда не переносится на Mac и не попадает в Git. Открытый сертификат доставляется по уже проверенному SSH-каналу: `scp devops:/etc/ssl/certs/devops.crt ~/devops.crt`. Проверка без отключения TLS: `curl --cacert ~/devops.crt -I https://devops.local`. Если сертификат будет пересоздан, заново скопировать его на Mac.

Для проверок ПР № 6 запустить на VM копию `scripts/audit.sh` без аргументов или с `--pr6`: дополнительно к ПР № 5 проверяются активность Nginx, синтаксис конфигурации, срок сертификата не менее 30 дней, отсутствие файлов с правом записи для всех и режим ключа `600`. Режим `--all` добавляет проверки Docker для ПР № 7.

На текущей VM аудит ПР № 6 показал `10 OK, 0 FAIL`, код `0`. При завышенном пороге проверки срока сертификата (`CERT_MIN_SECONDS=34560000`) получены `9 OK, 1 FAIL`, код `1`; при временном режиме `666` у `index.html` — также `9 OK, 1 FAIL`, код `1`. После каждого опыта исходные параметры восстановлены, повторный аудит дал код `0`.

Сценарий деплоя проверен всеми пятью случаями задания: `--dry-run` — код `0` без изменений сервера; зафиксированное изменение страницы — код `0` с новой версией на HTTPS; незакоммиченное и добавленное в индекс изменение — код `1` без синхронизации; остановленный Nginx — код `1` после синхронизации из-за неуспешного HTTP-запроса; зафиксированное удаление `site/index.html` — код `1` без синхронизации. После испытаний главная страница и Nginx восстановлены.

Проверены права: при файле `600` ответ `403` и запись `open() ... failed (13: Permission denied)`; при правах каталога `755/750/744/711` ответы соответственно `200/403/403/200`. У каталога `711` есть право прохода, но нет права перечисления; у `744` обратная ситуация. При прямой доставке `rsync` без `--chmod` файл с локальными правами `666` стал доступным для записи от `www-data`; процесс смог заменить страницу. Штатный деплой вернул исходное содержимое и права `644`, после чего запись от `www-data` снова отклонена.

Проверка журнала запросов дала ответы `200`, `301`, `403` и `404`; запросы `/admin`, `/wp-login.php` и `/.env` получили `404`. В записи журнала видны адрес клиента, дата и время, метод, путь, код, размер и User-Agent.

## 9. Подготовка к практической работе № 7

На ARM64 VM установлен Docker Engine из официального apt-репозитория Docker (пакеты `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`), а не `docker.io` Ubuntu. Воспроизводимый сценарий — `scripts/install-docker-engine.sh`; он добавляет ключ и deb822-источник пакетов, включает службы Docker и containerd и добавляет `devops` в группу `docker`. Установка проверена запуском `docker run --rm hello-world` от имени `devops` в новой SSH-сессии. Docker Engine 29.9.2, Compose v5.6.1 на дату установки.

Участник группы `docker` имеет фактически полномочия уровня root через сокет демона. Это нужно учитывать при работе с приложением из ПР № 7: Dockerfile описывает сборку образа, образ служит шаблоном, а контейнер — запущенным экземпляром. Прямой прокси работает от имени клиента, обратный прокси принимает запросы перед приложением; в ПР № 7 Nginx будет обратным прокси для контейнера. Текущий конфиг Nginx ещё не содержит `/app/`, и контейнер приложения пока не запущен.

## 10. Восстановление после отката

Для восстановления уже настроенного HTTPS использовать снимок `04-nginx-https`: сверить NAT-проброс 2222 → 2222, войти как `devops`, затем из чистой рабочей копии выполнить `scripts/deploy.sh`, чтобы заново доставить страницы. Снимок сохраняет сертификат и ключ, но после отката нужно убедиться, что копия `~/devops.crt` на Mac соответствует сертификату VM.

При восстановлении со снимка `03-ssh-hardened` после запуска повторить UFW и FQDN:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw logging medium
sudo ufw enable
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
sudo ufw status verbose
hostname -f
```

При откате к `01-clean-install` сначала изменить NAT-проброс на гостевой порт 22. На Mac из корня репозитория:

```bash
scp -P 2222 ~/.ssh/devops_vm.pub student@127.0.0.1:/tmp/devops_vm.pub
scp -P 2222 scripts/restore-server.sh student@127.0.0.1:/tmp/restore-server.sh
ssh -p 2222 student@127.0.0.1
```

В этой SSH-сессии на VM выполнить `sudo bash /tmp/restore-server.sh /tmp/devops_vm.pub`. Сценарий создаст devops, установит публичный ключ, настроит SSH, UFW и FQDN; он попросит пароль для новой учётной записи. Затем на Mac переключить NAT-проброс:

```bash
VBoxManage controlvm devops-vm natpf1 delete ssh
VBoxManage controlvm devops-vm natpf1 'ssh,tcp,127.0.0.1,2222,,2222'
ssh devops
```

Первую SSH-сессию не закрывать, пока новое подключение не проверено. При сообщении о смене ключа сервера сверить отпечаток в консоли VM; не удалять запись `known_hosts` автоматически. После восстановления проверить `sudo sshd -T`, `sudo ufw status verbose`, `hostname -f` и `bash ~/audit.sh --pr5`. Адрес `devops.local` в hosts Mac поправить, если DHCP выдаст VM другой Host-only IP.
