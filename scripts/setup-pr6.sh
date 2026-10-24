#!/usr/bin/env bash
# Run on the Ubuntu VM as root: bash setup-pr6.sh /tmp/pr6-nginx.conf
set -euo pipefail

config_source="${1:-}"
if [[ $EUID -ne 0 || ! -f "$config_source" ]]; then
    printf 'Usage: sudo bash %s PATH_TO_NGINX_CONFIG\n' "$0" >&2
    exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx rsync

install -d -o devops -g devops -m 755 /var/www/devops-site
if [[ ! -e /var/www/devops-site/index.html ]]; then
    printf '<h1>devops.local: placeholder</h1>\n' \
      > /var/www/devops-site/index.html
    chown devops:devops /var/www/devops-site/index.html
    chmod 644 /var/www/devops-site/index.html
fi

key=/etc/ssl/private/devops.key
cert=/etc/ssl/certs/devops.crt
if [[ ! -e "$key" && ! -e "$cert" ]]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
      -keyout "$key" -out "$cert" -subj '/CN=devops.local' \
      -addext 'subjectAltName=DNS:devops.local'
elif [[ ! -f "$key" || ! -f "$cert" ]]; then
    echo 'Only one TLS file exists; refusing to replace either file.' >&2
    exit 1
fi
chown root:root "$key" "$cert"
chmod 600 "$key"
chmod 644 "$cert"

install -o root -g root -m 644 "$config_source" \
  /etc/nginx/sites-available/devops-site
ln -sfn /etc/nginx/sites-available/devops-site \
  /etc/nginx/sites-enabled/devops-site
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx

printf '\n--- Nginx listeners ---\n'
ss -tlnp | grep nginx
printf '\n--- TLS files ---\n'
stat -c '%U:%G %a %n' "$key" "$cert"
printf '\n--- File access ---\n'
namei -l /var/www/devops-site/index.html
runuser -u www-data -- cat /var/www/devops-site/index.html
if runuser -u www-data -- touch /var/www/devops-site/write-test; then
    rm -f /var/www/devops-site/write-test
    echo 'www-data unexpectedly has write access' >&2
    exit 1
fi
printf '\nProvisioning completed.\n'
