#!/usr/bin/env bash
set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/vps/client.sh"
[[ $# -eq 0 ]] || fail 'vps-build.sh accepts no options'
enter_vps_environment "${BASH_SOURCE[0]}" "$@"
require_local_environment
acquire_local_lock
build_system
