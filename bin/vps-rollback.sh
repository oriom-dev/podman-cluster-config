#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/vps/client.sh"
enter_vps_environment "${BASH_SOURCE[0]}" "$@"
yes_option=
if [[ ${1:-} == --yes ]]; then
  yes_option=--yes
  shift
fi
[[ $# -ge 1 ]] || fail 'usage: vps-rollback.sh [--yes] TARGET [SSH_OPTION...]'
configure_vps "$@"
require_local_environment
acquire_local_lock
confirm_action rollback "$yes_option"

transaction_active=1
cleanup() {
  local status=$?
  trap - EXIT HUP INT TERM
  if (( transaction_active == 1 )); then
    note 'restoring the system active before this rollback'
    run_remote recover.sh || {
      printf 'critical: automatic recovery failed; run ./bin/vps-recover.sh\n' >&2
      status=1
    }
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

run_remote rollback.sh test
external_health
run_remote rollback.sh switch
external_health
run_remote rollback.sh complete

transaction_active=0
trap - EXIT HUP INT TERM
note 'rollback completed'
note 'revert the faulty main change and deploy it so Git and the active revision match again'
