#!/usr/bin/env bash
# Configuration audit for practical works 5 and 6. Exit 0: all checks pass; 1: failure.
set -uo pipefail
export LC_ALL=C
PASS=0
FAIL=0

check() {
    local description="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  [OK]   %s\n' "$description"
        ((PASS++))
    else
        printf '  [FAIL] %s (expected: %s, actual: %s)\n' "$description" "$expected" "$actual"
        ((FAIL++))
    fi
}

printf 'Configuration audit: %s, %s\n' "$(hostname -f)" "$(date '+%Y-%m-%d %H:%M')"
if ! sudo -v; then
    echo '[FAIL] Cannot obtain administrator privileges' >&2
    exit 1
fi
if ! ssh_config=$(sudo /usr/sbin/sshd -T 2>&1); then
    printf '[FAIL] Cannot read effective SSH configuration: %s\n' "$ssh_config" >&2
    exit 1
fi
if ! ufw_status=$(sudo /usr/sbin/ufw status verbose 2>&1); then
    printf '[FAIL] Cannot read firewall status: %s\n' "$ufw_status" >&2
    exit 1
fi
ssh_value() { awk -v field="$1" '$1 == field { print $2 }' <<< "$ssh_config"; }

echo '[1] SSH service'
check 'Root login disabled' no "$(ssh_value permitrootlogin)"
check 'Password authentication disabled' no "$(ssh_value passwordauthentication)"
# TODO 1 implemented: all configured SSH ports must be valid and different from 22.
port_ok=no
ports=$(ssh_value port)
if [[ -n "$ports" ]]; then
    port_ok=yes
    while IFS= read -r port; do
        if [[ ! "$port" =~ ^[0-9]+$ ]] || ((port == 22 || port < 1 || port > 65535)); then
            port_ok=no
        fi
    done <<< "$ports"
fi
check 'SSH port differs from 22' yes "$port_ok"
# TODO 2 implemented.
check 'MaxAuthTries equals 3' 3 "$(ssh_value maxauthtries)"

echo '[2] Firewall'
check 'Firewall active' active "$(awk '/^Status:/ {print $2}' <<< "$ufw_status")"
# TODO 3 implemented; LC_ALL=C ensures stable UFW output.
incoming_policy=$(sed -nE 's/^Default: ([^ ]+) \(incoming\).*/\1/p' <<< "$ufw_status")
check 'Default incoming policy is deny' deny "$incoming_policy"

echo '[3] User accounts'
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd
echo '[4] Web server'
check 'Nginx service active' active "$(systemctl is-active nginx 2>/dev/null || true)"
syntax=no
sudo /usr/sbin/nginx -t >/dev/null 2>&1 && syntax=yes
check 'Nginx configuration syntax valid' yes "$syntax"
# Override only the test threshold to demonstrate expiration failure.
CERT_MIN_SECONDS="${CERT_MIN_SECONDS:-2592000}"
cert_ok=no
if [[ "$CERT_MIN_SECONDS" =~ ^[0-9]+$ ]] && openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend "$CERT_MIN_SECONDS" >/dev/null 2>&1; then
    cert_ok=yes
fi
check 'Certificate valid beyond expiration threshold' yes "$cert_ok"
permissions_ok=no
if world_writable=$(find /var/www/devops-site -perm -o+w -print 2>/dev/null) &&
   key_permissions=$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null) &&
   [[ -z "$world_writable" && "$key_permissions" == 600 ]]; then
    permissions_ok=yes
fi
check 'No world-writable site paths; private key mode 600' yes "$permissions_ok"

printf 'Passed: %s, failed: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
