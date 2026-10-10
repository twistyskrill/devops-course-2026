#!/usr/bin/env bash
# Run as root after restoring 01-clean-install. Keep the current SSH session open.
set -euo pipefail
export LC_ALL=C
[[ $EUID -eq 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
[[ $# -eq 1 && -f $1 ]] || { echo 'Usage: sudo bash restore-server.sh PUBLIC_KEY_FILE' >&2; exit 1; }
ssh-keygen -lf "$1" >/dev/null
read -r -s -p 'New devops sudo password: ' devops_password
printf '\n'
read -r -s -p 'Confirm password: ' confirmation
printf '\n'
[[ -n "$devops_password" && "$devops_password" == "$confirmation" ]] || { echo 'Passwords do not match.' >&2; exit 1; }

id devops >/dev/null 2>&1 || adduser --disabled-password --gecos 'DevOps administrator' devops
usermod -aG sudo devops
printf 'devops:%s\n' "$devops_password" | chpasswd
unset devops_password confirmation
install -d -m 700 -o devops -g devops /home/devops/.ssh
install -m 600 -o devops -g devops "$1" /home/devops/.ssh/authorized_keys
[[ -f /etc/ssh/sshd_config.backup ]] || cp -a /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
for file in /etc/ssh/sshd_config.d/*.conf; do
    [[ "$file" == /etc/ssh/sshd_config.d/99-hardening.conf ]] && continue
    if grep -qE '^PasswordAuthentication[[:space:]]+yes' "$file"; then
        cp -a "$file" "${file}.before-hardening"
        sed -Ei 's/^PasswordAuthentication[[:space:]]+yes/# PasswordAuthentication yes - disabled for lab 5/' "$file"
    fi
done
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'CONF'
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
CONF
chmod 644 /etc/ssh/sshd_config.d/99-hardening.conf
/usr/sbin/sshd -t
ufw default deny incoming
ufw default allow outgoing
ufw limit 2222/tcp comment 'SSH rate-limited'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw logging medium
ufw --force enable
hostnamectl set-hostname devops-vm
sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
systemctl disable --now ssh.socket
systemctl enable --now ssh.service
systemctl restart ssh
echo 'Guest configured. Change NAT guest port 22 to 2222 on the host.'
echo 'Verify a NEW SSH session before closing the existing one.'
