# Настройка devops-vm на macOS — практическая работа № 5

Состояние проверено 24 октября 2026 года. Это новая виртуальная машина на Mac с Apple Silicon (M3). Прежняя работа на Windows, включая Nginx и Docker из практических работ № 6–7, сохранена в [архивном описании](server-setup-windows-archive.md). Команды и результаты из него **не относятся** к нынешней VM.

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

Порты 80 и 443 разрешены для будущего веб-сервера, но на этой VM Nginx пока не установлен. Правило SSH было создано **до** включения UFW. После активации проверено новое SSH-подключение. Запрос с Mac к `192.168.56.2:8080` заблокирован; `/var/log/ufw.log` содержит `SRC=192.168.56.1`, `DST=192.168.56.2`, `PROTO=TCP`, `DPT=8080`.

Проверить состояние:

```bash
sudo ufw status verbose
sudo ufw status numbered
sudo grep 'UFW BLOCK' /var/log/ufw.log | tail -5
```

При повторном создании правил использовать `sudo ufw limit 2222/tcp comment 'SSH rate-limited'` до `sudo ufw enable`; правило `ufw allow ssh` откроет стандартный порт 22 и здесь не подходит.

## 6. Снимки VirtualBox

| Снимок | Сохранённое состояние |
| --- | --- |
| `01-clean-install` | Установленная и обновлённая ОС, пользователь student, первоначальный SSH на порту 22 |
| `02-keys-configured` | Создан devops, добавлен публичный ключ, вход по ключу проверен |
| `03-ssh-hardened` | SSH на порту 2222, запрет root и пароля, новые подключения проверены |

UUID снимков текущей VM: `01-clean-install` — `48c02b8b-3260-4e67-ae05-ec5979e2aa3d`; `02-keys-configured` — `44fb20b2-a0c3-4c84-8af9-146f6d29709c`; `03-ssh-hardened` — `e714da24-c016-4ed7-b165-3675718c578b`. Они находятся только на этом Mac, в каталоге VirtualBox VM, а не в Git.

**Текущее рабочее состояние содержит также UFW и FQDN, но отдельного снимка после них пока нет.** Откат к `03-ssh-hardened` потеряет эти настройки. После отката проверить NAT-проброс и Host-only IP перед повторным SSH-входом.

## 7. Аудит для практической работы № 5

В `scripts/audit.sh` есть режим `--pr5`: он проверяет запрет root и пароля, нестандартный SSH-порт, `MaxAuthTries 3`, активность UFW и политику `deny incoming`. Список локальных пользователей выводится отдельно. При успехе ожидаются 6 OK, 0 FAIL и код выхода 0.

```bash
# На Mac из корня репозитория:
scp scripts/audit.sh devops:~/audit.sh
# В SSH-сессии devops на VM:
bash ~/audit.sh --pr5
echo $?
```

После временного изменения `MaxAuthTries` с 3 на 10 ожидаются 5 OK, 1 FAIL и код 1; затем вернуть 3. Для этой проверки достаточно временно изменить файл: `sshd -T` читает конфигурацию с диска, перезапуск SSH не нужен. Перед любым перезапуском службы снова выполнить `sudo sshd -t`. Полный режим `--all` (он же режим по умолчанию) сохранён для прежних работ № 6–7 и на нынешней VM закономерно обнаружит отсутствие Nginx и Docker.

## 8. Что ещё нужно для отчёта

Документ фиксирует конфигурацию. Для завершения самостоятельной части на **этой** VM остаётся выполнить положительный и отрицательный запуск аудита, зафиксировать вывод и восстановить `MaxAuthTries 3`. Факультативный SSH-туннель на новой VM ещё не проверялся. В отчёт нужны собственные скриншоты этой VM; скриншоты прежней Windows-работы не подтверждают текущее состояние.

## 9. Восстановление после отката

Самый короткий путь — снимок `03-ssh-hardened`. Сверить NAT-проброс: порт хоста 2222 → порт гостя 2222. После запуска войти как devops и повторить UFW и FQDN:

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
