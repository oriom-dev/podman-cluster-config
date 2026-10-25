#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/vps/client.sh"
enter_vps_environment "${BASH_SOURCE[0]}" "$@"
yes_option=
if [[ ${1:-} == --yes ]]; then
  yes_option=--yes
  shift
fi
[[ $# -ge 1 ]] || fail 'usage: vps-recover.sh [--yes] TARGET [SSH_OPTION...]'
configure_vps "$@"
require_local_environment
acquire_local_lock
confirm_action recover "$yes_option"
run_remote recover.sh
