# Конфигурация виртуальной машины devops-vm

Практическая работа № 5. Выполнил Кобзев Егор Максимович, ЭФБО-03-24.
Проверено 10 октября 2026 года на Windows и Ubuntu Server 24.04.5 LTS.

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
| devops | 1001 | devops, sudo, users | SSH только по Ed25519; пароль используется для sudo и консоли |
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
HTTP/HTTPS разрешены для будущей работы № 6; веб-сервер на этих портах пока не установлен.

## 7. Снимки состояния

Все три снимка созданы при выключенной гостевой ОС 10 октября 2026 года.

| Снимок | Момент создания | UUID |
| --- | --- | --- |
| 01-clean-install | Установленная и обновлённая ОС, student, SSH 22, оба адаптера | c39baea4-254e-4d5e-bcb6-1bba5b71185b |
| 02-keys-configured | devops в sudo, Ed25519, ssh devops проверен | 075ecf08-06c2-4433-b6f9-6df8f30cb494 |
| 03-ssh-hardened | SSH 2222, root и пароль запрещены, новые соединения проверены | 2a2f37a1-9c9c-41ef-a067-128c5095549f |

Текущее состояние после снимка 03 дополнительно содержит UFW, FQDN и аудит.
Восстановление 03 возвращает состояние **до** настройки UFW и локального имени.

## 8. Быстрое восстановление из 01-clean-install

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
На сервер передать `scripts/audit.sh`, затем:

```bash
bash scripts/audit.sh
echo $?
```

Ожидаются 6 успешных проверок и код 0. Процедура фактически проверена на
временном связанном клоне снимка 01: отдельный вход по ключу и все 6 проверок
прошли; запуск проверочного сценария занял 20,3 с, без времени клонирования.
Основная VM при этом не откатывалась. Для ручного выполнения учитывать ввод
паролей и время первого запуска, оставаясь в пределах отведённых 10 минут.

## 9. Проверка аудита и туннеля

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
