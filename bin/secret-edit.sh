#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/vps/client.sh"
enter_vps_environment "${BASH_SOURCE[0]}" "$@"
[[ $# -eq 1 ]] || fail 'usage: secret-edit.sh SERVICE'
[[ $1 =~ ^[a-z0-9-]+$ && -f "$REPO_ROOT/containers/$1/secrets.yaml" ]] ||
  fail "unknown service: $1"
export SOPS_AGE_KEY_FILE=${SOPS_AGE_KEY_FILE:-"$REPO_ROOT/.config/age.txt"}
exec sops --config "$REPO_ROOT/.sops.yaml" \
  "$REPO_ROOT/containers/$1/secrets.yaml"
