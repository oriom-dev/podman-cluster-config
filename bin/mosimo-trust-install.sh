#!/usr/bin/env bash
# Install the BSAF importer runtime material on kagoya-vps from the offline issuance
# directory (.config/mosimo-trust, produced by sd_2607/appview/bsaf/identity-cli.mjs).
#
# Copies only what the running services need:
#   credentials.json -> /var/lib/mosimo-importer/credentials.json  (publisher, root 0600)
#   roots.json       -> /var/lib/mosimo-importer/roots.json        (publisher, root 0600)
#   revocations.cbor -> /var/lib/mosimo-trust/revocations.cbor     (served by Caddy, root:caddy 0640)
# Root, CA, importer and PLC secrets never leave the local directory.
#
# usage: bin/mosimo-trust-install.sh [--no-restart] SSH_TARGET
set -euo pipefail

restart=1
if [[ ${1:-} == --no-restart ]]; then restart=0; shift; fi
[[ $# -eq 1 ]] || { echo 'usage: mosimo-trust-install.sh [--no-restart] SSH_TARGET' >&2; exit 1; }
target=$1
repo=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
source=${MOSIMO_PRIVATE_DIR:-$repo/.config/mosimo-trust}

for name in credentials.json roots.json revocations.cbor; do
  [[ -s $source/$name ]] || { echo "missing $source/$name (run identity-cli assemble / revocation-list)" >&2; exit 1; }
done
# Refuse to ship anything but worker material: a secret key field must not be in these files.
if grep -lE '"(secretKey|plcSecret)"' "$source/credentials.json" "$source/roots.json" >/dev/null; then
  echo 'refusing: root/CA/PLC secret fields found in runtime files' >&2; exit 1
fi

ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=15)
stage=/home/operator/.cache/mosimo-trust
ssh "${ssh_opts[@]}" "$target" "install -d -m 0700 $stage"
scp -q "${ssh_opts[@]}" "$source/credentials.json" "$source/roots.json" "$source/revocations.cbor" "$target:$stage/"
digest() { sha256sum "$1" | cut -d' ' -f1; }
ssh "${ssh_opts[@]}" "$target" bash -s -- "$(digest "$source/credentials.json")" "$(digest "$source/roots.json")" "$(digest "$source/revocations.cbor")" "$restart" <<'REMOTE'
set -euo pipefail
stage=/home/operator/.cache/mosimo-trust
check() { echo "$1  $2" | sha256sum --check --status; }
check "$1" $stage/credentials.json; check "$2" $stage/roots.json; check "$3" $stage/revocations.cbor
sudo install -d -m 0700 -o root -g root /var/lib/mosimo-importer
sudo install -d -m 0750 -o root -g caddy /var/lib/mosimo-trust
# Atomic replacement: readers always see a complete file.
sudo install -o root -g root -m 0600 $stage/credentials.json /var/lib/mosimo-importer/credentials.json.next
sudo install -o root -g root -m 0600 $stage/roots.json /var/lib/mosimo-importer/roots.json.next
sudo install -o root -g caddy -m 0640 $stage/revocations.cbor /var/lib/mosimo-trust/revocations.cbor.next
sudo mv /var/lib/mosimo-importer/credentials.json.next /var/lib/mosimo-importer/credentials.json
sudo mv /var/lib/mosimo-importer/roots.json.next /var/lib/mosimo-importer/roots.json
sudo mv /var/lib/mosimo-trust/revocations.cbor.next /var/lib/mosimo-trust/revocations.cbor
rm -f $stage/credentials.json $stage/roots.json $stage/revocations.cbor
if [[ $4 == 1 ]] && systemctl is-enabled --quiet mosimo-bsaf-publisher.service 2>/dev/null; then
  sudo systemctl restart mosimo-bsaf-publisher.service
fi
echo installed
REMOTE
