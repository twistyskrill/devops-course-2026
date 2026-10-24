#!/usr/bin/env bash
# Deploy the committed static site; use --dry-run before a new --delete target.
set -euo pipefail
trap 'status=$?; printf "Deploy failed (command exit %s)\n" "$status" >&2; exit 1' ERR
REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"
LOCAL_DIR="${ROOT_DIR}/site/"
dry_run=false
if (( $# > 1 )); then
    echo 'Usage: deploy.sh [--dry-run]' >&2; exit 1
fi
if (( $# == 1 )); then
    [[ "$1" == '--dry-run' ]] || { echo 'Unknown argument' >&2; exit 1; }
    dry_run=true
fi
[[ -f "${LOCAL_DIR}index.html" ]] || { echo 'Missing site/index.html; deployment refused' >&2; exit 1; }
[[ -z "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]] || {
    echo 'Uncommitted changes (including staged or untracked files); deployment refused' >&2
    exit 1
}
if ! $dry_run && [[ ! -r "$CA_CERT" ]]; then
    echo "Trusted certificate not readable: $CA_CERT" >&2; exit 1
fi
commit="$(git -C "$ROOT_DIR" rev-parse --short HEAD)"
args=(-avz --delete --chmod=D755,F644
      -e 'ssh -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1')
$dry_run && args+=(--dry-run)
# This is the only command that uses SSH. The trailing / copies site contents.
rsync "${args[@]}" "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"
if $dry_run; then
    printf 'Dry run complete for commit %s; remote contents unchanged\n' "$commit"
    exit 0
fi
curl --fail --silent --show-error --connect-timeout 15 --max-time 30 \
     --cacert "$CA_CERT" "$SITE_URL" --output /dev/null
printf 'Deployed commit %s; HTTPS certificate and HTTP status verified\n' "$commit"
