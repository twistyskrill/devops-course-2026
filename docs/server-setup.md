# Конфигурация виртуальной машины devops-vm

Практические работы № 5, № 6 и № 7. Выполнил Кобзев Егор Максимович, ЭФБО-03-24.
Проверено 17 октября 2026 года на Windows и Ubuntu Server 24.04.5 LTS.

## 1. Параметры машины

| Параметр | Значение |
| --- | --- |
| Гипервизор | Oracle VirtualBox 7.1.6 r167084 |
| Имя VM | devops-vm |
| ОС | Ubuntu Server 24.04.5 LTS amd64, стандартная редакция без GUI |
| Ядро | 6.8.0-146-generic |
| RAM | 2048 МБ |
| CPU | 2 ядра |
| Диск | 25 ГБ, динамический VDI, весь виртуальный диск, ext4 |
| Имя узла | devops-vm |
| FQDN | devops-vm.devops.local |
| Часовой пояс | Europe/Moscow |
| Паравиртуализация | None (`--paravirtprovider none`) |

На этом Windows-хосте обнаружен активный гипервизор. При режиме KVM/default
загрузка несколько раз зависала с трассировкой `default_idle`. Успешная загрузка
получена после смены режима VM на None. Также сохранён `nomodeset` в
`/etc/default/grub.d/99-devops-console.cfg`, затем выполнен `sudo update-grub`.
После отката на первый или второй снимок обязательно снова установить None
**до запуска VM**: эти снимки были созданы до смены режима.

## 2. Сетевые интерфейсы

| Интерфейс | Режим | IPv4 | Назначение |
| --- | --- | --- | --- |
| enp0s3 | NAT | 10.0.2.15/24, DHCP | Доступ к интернету и SSH через проброс |
| enp0s8 | Host-only | 192.168.56.101/24, DHCP | Прямой доступ с Windows-хоста |
| lo | Loopback | 127.0.0.1/8 | Локальные службы и SSH-туннель |

Host-only адаптер Windows: `VirtualBox Host-Only Ethernet Adapter`,
адрес `192.168.56.1/24`. DHCP VirtualBox: `192.168.56.100`, пул
`192.168.56.101-192.168.56.254`. После отката/переноса проверить адрес
`ip -brief address`; если он изменился, обновить запись Windows hosts.

## 3. Правило проброса портов

| Состояние | Имя | Протокол | Хост | Порт хоста | Порт гостя |
| --- | --- | --- | --- | --- | --- |
| После установки, снимки 01 и 02 | ssh | TCP | 127.0.0.1 | 2222 | 22 |
| После hardening, снимок 03 и текущее | ssh | TCP | 127.0.0.1 | 2222 | 2222 |

Адрес гостя в правиле не задан. Проброс слушает только loopback Windows.

## 4. Учётные записи

| Учётная запись | UID | Группы | Аутентификация |
| --- | --- | --- | --- |
| student | 1000 | student, adm, cdrom, sudo, dip, plugdev, lxd | Пароль в консоли; SSH после hardening запрещён AllowUsers |
| devops | 1001 | devops, sudo, users, docker (после ПР № 6) | SSH только по Ed25519; пароль используется для sudo и консоли |
| root | 0 | root | Прямой SSH-вход запрещён |

Приватный ключ находится **только на Windows-хосте**:
`C:\Users\egork\.ssh\devops_vm`. Публичный ключ:
`C:\Users\egork\.ssh\devops_vm.pub`. На VM установлен только публичный ключ
`/home/devops/.ssh/authorized_keys`; владелец devops, права 600; каталог `.ssh` 700.
Пароли и приватный ключ в репозиторий не включаются.

Отпечаток Ed25519 ключа сервера:
`SHA256:NInUh0K3F4Q3HEt8A62BZfdLn6dj1guSHgGrljsHy9w`.
Он сверен с `sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` в консоли VM.

Windows-файл `C:\Users\egork\.ssh\config`:

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

Host devops.local
    HostName devops.local
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Windows hosts: `C:\Windows\System32\drivers\etc\hosts`:

```text
192.168.56.101 devops.local
```

В гостевом `/etc/hosts`: `127.0.1.1 devops-vm.devops.local devops-vm`.
`devops.local` здесь разрешается статическим hosts, DNS-сервер не развёрнут.

## 5. Служба SSH

Основной `/etc/ssh/sshd_config` сохранён без изменений, его резервная копия:
`/etc/ssh/sshd_config.backup`. Конфигурация усиления защиты:
`/etc/ssh/sshd_config.d/99-hardening.conf`, владелец root, права 644, окончания LF.

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
LogLevel VERBOSE
```

В `/etc/ssh/sshd_config.d/50-cloud-init.conf` закомментирована исходная строка
`PasswordAuthentication yes`. Первое прочитанное значение имеет приоритет;
проверять нужно `sudo sshd -T`, а не только текст файла 99-hardening.conf.
Копия cloud-init файла: `50-cloud-init.conf.before-hardening`.
`KbdInteractiveAuthentication no` уже задана штатной конфигурацией.

```bash
sudo sshd -t
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd
sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)'
```

Фактически слушаются `0.0.0.0:2222` и `[::]:2222`. До подтверждения нового
подключения старую SSH-сессию не закрывать. С Windows `ssh devops` работает;
root и клиент с `PubkeyAuthentication=no` получают `Permission denied (publickey)`.
До hardening сервер предлагал `publickey,password`, после - только `publickey`.
В журнале различаются запрет root по AllowUsers и разрыв соединения devops
до завершения аутентификации. Записи `Failed password` нет, поскольку пароль
не является разрешённым методом и не передаётся серверу.

## 6. Правила межсетевого экрана

UFW активен. Политики: deny incoming, allow outgoing, disabled routed.
Регистрация: medium. Для IPv4 и IPv6 настроены:

| Порт | Действие | Комментарий |
| --- | --- | --- |
| 2222/tcp | LIMIT IN | SSH rate-limited |
| 80/tcp | ALLOW IN | HTTP |
| 443/tcp | ALLOW IN | HTTPS |

Правило SSH создаётся **до** включения UFW. `ufw allow ssh` здесь непригодна,
поскольку имя ssh в `/etc/services` соответствует порту 22.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw logging medium
sudo ufw enable
sudo ufw status verbose
```

`curl.exe -m 3 http://192.168.56.101:8080` завершился тайм-аутом.
В `/var/log/ufw.log` зафиксированы `SRC=192.168.56.1`,
`DST=192.168.56.101`, `PROTO=TCP`, `DPT=8080`.
В ПР № 5 порты HTTP/HTTPS открыты заранее; текущее состояние Nginx описано в разделе 8.

## 7. Снимки состояния

Все три снимка созданы при выключенной гостевой ОС 10 октября 2026 года.

| Снимок | Момент создания | UUID |
| --- | --- | --- |
| 01-clean-install | Установленная и обновлённая ОС, student, SSH 22, оба адаптера | c39baea4-254e-4d5e-bcb6-1bba5b71185b |
| 02-keys-configured | devops в sudo, Ed25519, ssh devops проверен | 075ecf08-06c2-4433-b6f9-6df8f30cb494 |
| 03-ssh-hardened | SSH 2222, root и пароль запрещены, новые соединения проверены | 2a2f37a1-9c9c-41ef-a067-128c5095549f |
| 03b-pr5-complete | Полное состояние ПР № 5 до отката для ПР № 6 | fa7aa678-270d-4cf9-8daf-ac5beed2db4c |
| 04-nginx-https | Nginx, SAN, HTTPS и HTTP 301; временная главная страница | 259aad34-adbd-4e43-9c1f-83d08da3a510 |
| 04b-pr6-complete | Полное состояние ПР № 6 перед контейнеризацией | db877df6-484c-4fc9-ae24-ddf2730bf186 |
| 05-docker-compose | Приложение и БД, том, Nginx proxy, аудит 14 OK | ade7c50f-5939-4844-97ed-89df70454f3b |

Текущее состояние ПР № 6 содержит UFW, FQDN, Nginx, итоговый сайт, расширенный аудит и Docker.
Снимок 03b сохраняет полное состояние ПР № 5.
Восстановление 03 возвращает состояние **до** настройки UFW и локального имени.

## 8. Веб-сервер

Практическая работа № 6 выполнена 10 октября 2026 года. Основная VM действительно
восстановлена из `01-clean-install` по инструкции раздела 10; SSH, UFW и FQDN
повторно проверены до установки Nginx. Полное состояние ПР № 5 отдельно сохранено
в снимке `03b-pr5-complete`. Аудит до установки Nginx использовался из коммита
`35b05c4` и давал 6 OK; текущая версия проверяет также веб-сервер и даёт 10 OK.

### Параметры и модель прав

| Параметр | Фактическое значение |
| --- | --- |
| Пакет | `nginx`, версия 1.24.0, пакет Ubuntu `1.24.0-2ubuntu7.18` |
| Служба | `nginx.service`, включена и активна |
| Конфигурация | `/etc/nginx/sites-available/devops-site` |
| Активная ссылка | `/etc/nginx/sites-enabled/devops-site` |
| Конфигурация в Git | `config/nginx/devops-site.conf` |
| Стандартный ресурс | ссылка `sites-enabled/default` удалена; `sites-available/default` сохранён |
| Имя и порты | `devops.local`, TCP 80 и 443, IPv4 и IPv6 |
| HTTP | 301 на `https://$host$request_uri` |
| HTTPS | TLS 1.2 и 1.3; при проверке согласован TLS 1.3 |
| Каталог | `/var/www/devops-site`, владелец `devops:devops`, 755 |
| Файлы | `index.html`, `404.html`, владелец `devops:devops`, 644 |
| Сертификат | `/etc/ssl/certs/devops.crt`, `root:root`, 644 |
| Закрытый ключ | `/etc/ssl/private/devops.key`, `root:root`, 600 |
| Срок сертификата | 365 дней, 10.10.2026 17:43:32 UTC — 10.10.2027 17:43:32 UTC |
| SAN | `DNS:devops.local` |
| Журналы | `/var/log/nginx/devops-site.access.log`, `devops-site.error.log` |

Master работает от root, workers от www-data. Рабочий процесс читает страницы,
но не может менять файлы или создавать их в каталоге. Ключ читает master.
Закрытый ключ не копируется на хост и не добавляется в Git.
HSTS не включён. Профили UFW Nginx не добавлялись: 80 и 443 уже разрешены.
В блоке HTTP также задан журнал ресурса, поэтому распределение его кодов
включает перенаправления 301, а не только ответы HTTPS.

### Воспроизведение установки

```bash
# VM, после восстановления ПР № 5
sudo apt update && sudo apt install -y nginx rsync
sudo install -d -o devops -g devops -m 755 /var/www/devops-site
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
sudo chown root:root /etc/ssl/private/devops.key /etc/ssl/certs/devops.crt
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
```

Передать конфигурацию из Git на VM через SSH и установить:

```bash
# Хост WSL, корень репозитория
scp config/nginx/devops-site.conf devops:/tmp/devops-site.conf
# VM
sudo install -o root -g root -m 644 /tmp/devops-site.conf /etc/nginx/sites-available/devops-site
sudo ln -sfn /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/devops-site
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

Конфигурация состоит из HTTP-блока с `return 301 https://$host$request_uri` и
HTTPS-блока с `root /var/www/devops-site`, `index index.html`,
`location / { try_files $uri $uri/ =404; }`, `error_page 404 /404.html`.
Полный готовый файл находится в `config/nginx/devops-site.conf`.
Перед любым применением изменений обязательно `nginx -t`; затем reload.

### Хост Windows и доставка

Установлена отдельная `Ubuntu-24.04` **WSL версии 1**; существующая
`docker-desktop` версии 2 не изменялась. Запуск подготовленной среды:

```powershell
wsl -d Ubuntu-24.04 -u root
```

В WSL находятся rsync 3.2.7, Git, OpenSSH, curl 8.5.0, OpenSSL.
SSH-ключ скопирован в `/root/.ssh/devops_vm` (600); каталог `.ssh` — 700.
Конфигурация и known_hosts перенесены с Windows: отпечаток сервера уже проверен.
В WSL alias `devops` направлен на Host-only `192.168.56.101:2222`;
Windows alias `devops` по-прежнему использует NAT `127.0.0.1:2222`.
Для повторного использования соединения в WSL заданы `ControlMaster auto`,
`ControlPersist 600`, `ControlPath /root/.ssh/cm-%C`.
Если DHCP-адрес изменился, обновить WSL SSH config и Windows hosts.
`devops.local` в WSL разрешается в 192.168.56.101.

```bash
# WSL, корень репозитория; сертификат передаётся только по проверенному SSH
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
git config core.fileMode false
git config core.autocrlf input
rsync -avz --delete --chmod=D755,F644 --dry-run site/ devops:/var/www/devops-site/
scripts/deploy.sh --dry-run
scripts/deploy.sh
curl --cacert ~/devops.crt -I https://devops.local
```

Для общего каталога Windows/WSL согласован `core.autocrlf input`;
`.gitattributes` также принудительно хранится с LF. Это исключает ложное
изменение самого файла атрибутов после checkout средствами Windows Git.
На `/mnt/c` исходные файлы имеют права 777; параметр `--chmod` устанавливает
755/644 на сервере. Сценарий работает из подкаталогов, отказывает при отсутствии
index.html и при любых изменениях Git (рабочих, staged, untracked). Вызов rsync
открывает не более одного SSH-соединения, с BatchMode и ConnectTimeout=5.
Проверка curl использует доверенный сертификат, `--fail` и тайм-ауты.
Успех печатает короткий хеш и возвращает 0; отказ — 1; dry-run не делает HTTP-запрос.
При UFW LIMIT остановить частые попытки и выдержать паузу; защиту не отключать.

### Аудит, опыты и снимок

Раздел `[4] Web server` в `scripts/audit.sh` проверяет active nginx, `nginx -t`,
не менее 30 дней срока сертификата (2592000 секунд), отсутствие `o+w` в каталоге
и права ключа 600. Для теста срока существует `CERT_MIN_SECONDS`:

```bash
scripts/audit.sh                             # 10 OK, код 0
CERT_MIN_SECONDS=34560000 scripts/audit.sh    # 400 дней: 9 OK, 1 FAIL, код 1
chmod 666 /var/www/devops-site/index.html
scripts/audit.sh                             # 9 OK, 1 FAIL, код 1
chmod 644 /var/www/devops-site/index.html
scripts/audit.sh                             # снова 10 OK, код 0
```

Фактические опыты: файл 600 → HTTP 403 и `open() ... failed (13: Permission denied)`;
каталог 755 → 200, 750 → 403, 744 → 403, 711 → 200.
Без `--chmod` rsync перенёс 777, www-data успешно записал `<h1>defaced</h1>`.
Штатный deploy восстановил HTML и 755/644; `find -perm -o+w` пуст;
`sudo -u www-data touch .../index.html` получает Permission denied.

Снимок `04-nginx-https` создан при выключенной VM после проверки HTTPS и SAN,
до доставки итогового site/. Конфигурация, сертификат и снимки сохранены.
После отката к ранним снимкам сохранить параметры консоли перед следующей перезагрузкой:

```bash
printf 'GRUB_CMDLINE_LINUX_DEFAULT="nomodeset"\nGRUB_GFXMODE=1280x800\nGRUB_GFXPAYLOAD_LINUX=keep\n' \
  | sudo tee /etc/default/grub.d/99-devops-console.cfg
sudo update-grub
```

### Подготовка ПР № 7

Docker Engine 29.9.0 установлен из официального APT-репозитория
`https://download.docker.com/linux/ubuntu`, suite noble, component stable,
ключ `/etc/apt/keyrings/docker.asc`, источник `/etc/apt/sources.list.d/docker.sources`.
Пакеты: docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin,
docker-compose-plugin. Пакет docker.io не использовался.
devops включён в docker; новый SSH-вход выполнил `docker run hello-world` без sudo.
Группа docker даёт фактические возможности root через привилегированный daemon
и монтирование файлов хоста; это расширение полномочий учётной записи.
Порты контейнеров не публиковались. UFW остаётся активным; в будущих работах
учитывать, что опубликованные Docker-порты могут обходить его обычные правила.


## 9. Контейнеризация

Практическая работа № 7 выполнена 17 октября 2026 года. Код находится в `app/`,
рабочий каталог на VM — `/home/devops/app`, проект Compose называется `app`.
Состояние ПР № 6 сохранено отдельно как `04b-pr6-complete`; снимок
`05-docker-compose` сохраняет приложение, СУБД и именованный том для следующих работ.

### Docker Engine и привилегии

Установлен официальный Docker Engine 29.9.0, Compose v5.6.0. Источник APT —
`https://download.docker.com/linux/ubuntu`, suite `noble`, component `stable`,
ключ `/etc/apt/keyrings/docker.asc`, файл `/etc/apt/sources.list.d/docker.sources`.
Пакеты: `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`,
`docker-compose-plugin`; пакет `docker.io` не используется. Восстановление на новой VM:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker devops
```

Начать новую SSH-сессию и выполнить `id`, `docker version`, `docker compose version`,
`docker run --rm hello-world` без sudo. У devops уже есть sudo. Группа docker даёт
фактические права root через Docker daemon и монтирование файловой системы хоста;
добавлять в неё обычные непривилегированные учётные записи нельзя.

### Образ и доставка исходников

`app/Dockerfile` использует `python:3.12-slim`, устанавливает зависимости до
копирования кода, затем задаёт `USER app` и exec-форму CMD Gunicorn на порту 5000.
Версии зависимостей: Flask 3.0.3, psycopg2-binary 2.9.9, Gunicorn 22.0.0.
Файлы образа принадлежат root и имеют 644; процесс app читает их, но не меняет.
При изменении только app.py установка зависимостей повторно берётся из кэша.
Теги базовых образов фиксируют ветку версии, но не digest; для строгой побитовой
воспроизводимости в дальнейшем следует закрепить digest и транзитивные зависимости.

На хосте WSL, из корня Git-репозитория:

```bash
rsync -avz --delete --exclude=.env --chmod=D755,F644 --dry-run app/ devops:app/
rsync -avz --delete --exclude=.env --chmod=D755,F644 app/ devops:app/
```

`--exclude=.env` также защищает серверный файл от удаления при `--delete`.
`--chmod` нормализует права при доставке из Windows. Корневая `.gitignore`
и `app/.dockerignore` исключают `.env`; содержимое секрета не копируется на хост
и не включается в образ. Изолированный контейнер без СУБД отвечает `ok` на
`/health`, а `/` возвращает 500: localhost внутри него не является адресом VM.

### Серверный секрет и Compose

Первоначально, только на VM от devops:

```bash
cd ~/app
umask 077
cp .env.example .env
chmod 600 .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
docker compose up -d --build
docker compose ps
docker compose exec -T app id
```

Содержимое `.env` не выводить и не публиковать. При обычной повторной доставке
существующий секрет сохраняется; генерация нового пароля при старом томе СУБД
потребует согласованного изменения пароля роли PostgreSQL. `env_file` передаёт
переменные в контейнеры; доступ к Docker API поэтому также означает доступ к ним.

| Объект | Настройка |
| --- | --- |
| `app-app-1` | `devops-app:1.0`, Gunicorn, UID 999 `app` |
| Порт приложения | `127.0.0.1:5000:5000`, доступен локальному Nginx |
| `app-db-1` | `postgres:16-alpine`, порт 5432 на VM не опубликован |
| Сеть | `app_backend`, пользовательская bridge; DNS-имя БД `db` |
| Том | `app_db_data`, точка в контейнере `/var/lib/postgresql/data` |
| Проверка БД | `pg_isready`, interval 5s, timeout 3s, retries 5 |
| Запуск приложения | `depends_on: db: condition: service_healthy` |
| Перезапуск | у обоих сервисов `restart: unless-stopped` |

Полная конфигурация хранится в `app/docker-compose.yml`. В healthcheck запись
`$${POSTGRES_USER}` оставляет раскрытие переменной оболочке контейнера.
Проверка `service_healthy` ждёт первоначальной готовности БД; она не заменяет
обработку последующих отказов приложением. `/health` проверяет веб-процесс,
а запрос `/` дополнительно проверяет доступность записи и чтения в БД.

```bash
cd ~/app
docker compose exec -T app getent hosts db
sudo ss -tlnp | grep -E ':(5000|5432)\b'
for i in 1 2 3; do curl -fsS http://127.0.0.1:5000/; done
docker compose down
docker volume ls
docker compose up -d
curl -fsS http://127.0.0.1:5000/
```

Счётчик сохраняется после `down` и увеличивается после `up`. В обязательном
опыте только с новой учебной БД `down -v` удалил том, и следующий запрос после
`up -d` дал 1. После опыта проект и новый том оставлены. В повседневной работе
не применять `-v`, поскольку он уничтожает данные.

### Nginx и проверка отказа

В HTTPS-блок `/etc/nginx/sites-available/devops-site` добавлен только маршрут:

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Полный конфигурационный файл — `config/nginx/devops-site.conf`. Перед применением:

```bash
# Хост
scp config/nginx/devops-site.conf devops:/tmp/devops-site.conf
# VM
sudo install -o root -g root -m 644 /tmp/devops-site.conf /etc/nginx/sites-available/devops-site
sudo nginx -t && sudo systemctl reload nginx
# Хост WSL
curl --cacert ~/devops.crt https://devops.local/app/
curl --cacert ~/devops.crt https://devops.local/app/health
curl --cacert ~/devops.crt -I https://devops.local/
```

Завершающий `/` в proxy_pass преобразует `/app/health` в `/health`.
Статическая главная страница и TLS из ПР № 6 сохранены. При остановке сервиса
`docker compose stop app` запрос через Nginx получает 502, а error.log содержит
`connect() failed (111: Connection refused) while connecting to upstream`.
После `docker compose start app` проксирование восстанавливается.

Опыт с временным `-p 5001:5000` показал ответ с хоста без правила UFW для 5001:
Docker создаёт DNAT и собственные правила пересылки раньше обработки UFW.
Тестовый контейнер `exposed` остановлен; в итоговой конфигурации 5000 привязан
только к loopback, БД не публикуется. Не полагаться на UFW для защиты публикаций Docker.

### Аудит и восстановление

Раздел `[5] Containers` в `scripts/audit.sh` проверяет Docker active,
`app-db-1` healthy, отсутствие слушателей 5000/5432 за пределами 127.0.0.1
и права `/home/devops/app/.env` 600. Итог — 14 OK, 0 FAIL, код 0.
Для отрицательного опыта публикация временно заменялась на `5000:5000`:
появились `0.0.0.0:5000` и `[::]:5000`, проверка портов вернула FAIL и код 1.
После восстановления безопасного Compose аудит снова возвращает 0.
Проверка порта не заменяет `compose ps` и HTTP-запросы: отсутствие слушателя
само по себе не доказывает работоспособность приложения.

Для восстановления с `01-clean-install` выполнить раздел 10 (SSH, UFW, FQDN),
раздел 8 (Nginx и TLS), затем этот раздел: установка Docker, доставка `app/`,
создание серверного `.env`, `compose up -d --build`, добавление proxy location,
аудит и запросы HTTPS. Для сохранения существующих данных предпочтителен снимок
`05-docker-compose` либо резервная копия PostgreSQL; из Git восстанавливаются
код и конфигурация, но не секрет и не содержимое тома.

## 10. Быстрое восстановление из 01-clean-install

На Windows оставить текущий SSH-ключ. Пароль student взять из личных локальных
данных доступа. После выключения VM, в PowerShell:

```powershell
$vboxForLab = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
& $vboxForLab snapshot devops-vm restore 01-clean-install
& $vboxForLab modifyvm devops-vm --paravirtprovider none
& $vboxForLab startvm devops-vm --type headless
```

Откат снимка также восстанавливает NAT-проброс на гостевой порт 22.
Если SSH показывает смену ключа, сначала сверить отпечаток в консоли VM;
не удалять known_hosts автоматически. В этих снимках ключ сервера один и тот же.

Из каталога локальной копии репозитория на Windows передать файлы:

```powershell
scp -P 2222 "$env:USERPROFILE\.ssh\devops_vm.pub" student@127.0.0.1:/tmp/devops_vm.pub
scp -P 2222 scripts/restore-server.sh student@127.0.0.1:/tmp/restore-server.sh
ssh student@127.0.0.1 -p 2222
```

В открытой SSH-сессии student:

```bash
sudo bash /tmp/restore-server.sh /tmp/devops_vm.pub
# Ввести пароль student для sudo, затем дважды новый пароль devops для sudo.
```

Скрипт создаёт devops, устанавливает публичный ключ и права, устраняет конфликт
cloud-init, записывает hardening, проверяет синтаксис, задаёт UFW и FQDN,
переключает ssh.socket на ssh.service. Сессию student пока не закрывать.
В другом PowerShell изменить активный проброс:

```powershell
& $vboxForLab controlvm devops-vm natpf1 delete ssh
& $vboxForLab controlvm devops-vm natpf1 'ssh,tcp,127.0.0.1,2222,,2222'
ssh devops
ssh devops.local
```

Проверить Host-only IP и при необходимости поправить hosts Windows.
Для базовой проверки восстановления до Nginx использовать версию аудита из ПР № 5:
`git show 35b05c4:scripts/audit.sh > /tmp/audit-pr5.sh`, передать её на VM:
`scp /tmp/audit-pr5.sh devops:/home/devops/audit-pr5.sh`. Текущий расширенный аудит ожидает установленный Nginx из раздела 8. Затем:

```bash
bash /home/devops/audit-pr5.sh
echo $?
```

Ожидаются 6 успешных проверок и код 0. Процедура фактически проверена на
временном связанном клоне снимка 01: отдельный вход по ключу и все 6 проверок
прошли; запуск проверочного сценария занял 20,3 с, без времени клонирования.
Во время проверки ПР № 5 основная VM не откатывалась; в начале ПР № 6
откат и восстановление основной VM выполнены, что отражено в разделе 8. Для ручного выполнения учитывать ввод
паролей и время первого запуска, оставаясь в пределах отведённых 10 минут.

## 11. Проверка аудита и туннеля

`scripts/audit.sh` читает действующую конфигурацию `sshd -T` и UFW.
`LC_ALL=C` обеспечивает стабильный разбор вывода UFW.
На правильной конфигурации: 6 OK, код 0. При временном `MaxAuthTries 10`:
5 OK и 1 FAIL, код 1. После восстановления `MaxAuthTries 3` снова код 0.
Перед проверкой ошибок убедиться, что файл конфигурации использует LF:
в первом опыте окончания CRLF препятствовали замене строки регулярным выражением.

Факультативный туннель проверен:

```bash
# На VM, в отдельной сессии
mkdir -p ~/restricted
echo '<h1>Ресурс доступен только через туннель</h1>' > ~/restricted/index.html
python3 -m http.server 8080 --bind 127.0.0.1 --directory ~/restricted
```

```powershell
# На Windows, отдельная сессия
ssh -L 9090:127.0.0.1:8080 -N devops
# В другом окне
curl.exe -s http://127.0.0.1:9090
```

Получен HTML ресурса. Снаружи 8080 закрыт, клиент входит через разрешённый SSH 2222,
а sshd соединяется с HTTP-сервером по loopback VM. После демонстрации туннель
и временный HTTP-процесс остановлены; файл страницы сохранён.
