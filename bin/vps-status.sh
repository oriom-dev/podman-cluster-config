#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/vps/client.sh"
enter_vps_environment "${BASH_SOURCE[0]}" "$@"
[[ $# -ge 1 ]] || fail 'usage: vps-status.sh TARGET [SSH_OPTION...]'
configure_vps "$@"
require_local_environment
acquire_local_lock

local_commit=$(git -C "$REPO_ROOT" rev-parse HEAD)
remote_commit=$(live_main_commit)
if [[ -z $(git -C "$REPO_ROOT" status --porcelain=v1 --untracked-files=all) ]]; then
  local_tree=clean
else
  local_tree=dirty
fi
printf 'local_commit=%s\nlive_main=%s\nlocal_tree=%s\n' \
  "$local_commit" "$remote_commit" "$local_tree"
run_remote status.sh
