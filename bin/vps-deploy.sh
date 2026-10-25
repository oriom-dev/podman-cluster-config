#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/vps/client.sh"
enter_vps_environment "${BASH_SOURCE[0]}" "$@"
yes_option=
if [[ ${1:-} == --yes ]]; then
  yes_option=--yes
  shift
fi
[[ $# -ge 1 ]] || fail 'usage: vps-deploy.sh [--yes] TARGET [SSH_OPTION...]'
configure_vps "$@"
require_local_environment
acquire_local_lock
confirm_action deploy "$yes_option"

commit=$(release_commit)
system_path=$(build_system)
[[ $commit == "$(release_commit)" ]] || fail 'repository tip changed during the build'

note 'verifying strict SSH access'
ssh "${SSH_OPTIONS[@]}" "$VPS_TARGET" true
copy_system "$system_path"

transaction_active=1
cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  if (( transaction_active == 1 )); then
    note 'restoring the system active before this deployment'
    run_remote recover.sh || {
      printf 'critical: automatic recovery failed; run ./bin/vps-recover.sh\n' >&2
      status=1
    }
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

run_remote deploy.sh test "$commit" "$system_path"
external_health deployment
run_remote deploy.sh switch "$commit" "$system_path"
external_health deployment
run_remote deploy.sh complete "$commit" "$system_path"

transaction_active=0
trap - EXIT HUP INT TERM
note "deployed $commit"
