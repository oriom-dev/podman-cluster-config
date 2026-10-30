#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/vps/client.sh"
enter_vps_environment "${BASH_SOURCE[0]}" "$@"
[[ $# -eq 1 ]] || fail 'usage: secret-edit.sh SERVICE'
case $1 in
  jpost-api|mc-whitelist-auth|mc-whitelist-db|mc-velocity) ;;
  *) fail "unknown service: $1" ;;
esac
exec sops --config "$REPO_ROOT/containers/.sops.yaml" \
  "$REPO_ROOT/containers/$1/secrets.yaml"
