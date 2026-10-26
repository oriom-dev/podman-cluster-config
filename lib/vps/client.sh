#!/usr/bin/env bash

LIB_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "$LIB_DIR/../.." && pwd -P)
readonly REPO_ROOT
readonly REMOTE_DIR="$LIB_DIR/remote"
readonly LOCAL_STATE_DIR=${XDG_STATE_HOME:-"$HOME/.local/state"}/oriom-vps
readonly BUILD_DIR="$REPO_ROOT/build"
readonly RESULT_LINK="$BUILD_DIR/kagoya-vps"

VPS_TARGET=
NIX_SSH_OPTIONS=
SSH_OPTIONS=()

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '==> %s\n' "$*" >&2
}

enter_vps_environment() {
  local script=$1
  shift
  [[ $(uname -s) == Linux ]] || fail 'run this command from Linux or WSL'
  case "$REPO_ROOT" in
    /mnt/*) fail 'clone the repository into the native WSL filesystem before building' ;;
  esac
  [[ ${ORIOM_VPS_ENV:-0} == 1 ]] && return
  command -v nix >/dev/null 2>&1 || fail 'Nix is required'
  exec nix \
    --extra-experimental-features 'nix-command flakes' \
    shell --no-update-lock-file --no-write-lock-file \
    --builders '' "$REPO_ROOT#vps" \
    --command env ORIOM_VPS_ENV=1 bash "$script" "$@"
}

require_local_environment() {
  git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null
  [[ -f $REMOTE_DIR/host.sh ]] || fail 'missing VPS support files'
}

configure_vps() {
  local option
  [[ $# -ge 1 && $1 != -* ]] || fail 'missing SSH target'
  VPS_TARGET=$1
  shift
  SSH_OPTIONS=("$@")
  NIX_SSH_OPTIONS=
  for option in "$@"; do
    NIX_SSH_OPTIONS+=" $option"
  done
}

acquire_local_lock() {
  mkdir -p "$LOCAL_STATE_DIR"
  exec 8>"$LOCAL_STATE_DIR/operation.lock"
  flock -n 8 || fail 'another VPS operation is already running'
}

confirm_action() {
  local action=$1 option=${2:-} reply
  [[ $option == --yes ]] && return
  [[ -z $option ]] || fail "unknown option: $option"
  [[ -t 0 ]] || fail "$action requires an interactive terminal or --yes"
  printf 'Type %s to continue: ' "$action"
  read -r reply
  [[ $reply == "$action" ]] || fail "$action cancelled"
}

live_main_commit() {
  local line
  line=$(git ls-remote --exit-code \
    https://github.com/oriom-dev/podman-cluster-config.git refs/heads/main) ||
    fail 'failed to resolve GitHub main'
  [[ -n $line ]] || fail 'GitHub main did not resolve to a commit'
  printf '%s\n' "${line%%[[:space:]]*}"
}

release_commit() {
  local branch upstream origin_url commit remote_commit
  [[ -z $(git -C "$REPO_ROOT" status --porcelain=v1 --untracked-files=all) ]] ||
    fail 'deploy requires a clean working tree'
  branch=$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD) ||
    fail 'deploy requires an attached branch'
  [[ $branch == main ]] || fail "deploy requires branch main, found $branch"
  upstream=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) ||
    fail 'main must track origin/main'
  [[ $upstream == origin/main ]] || fail "main must track origin/main, found $upstream"
  origin_url=$(git -C "$REPO_ROOT" remote get-url origin)
  case "$origin_url" in
    https://github.com/oriom-dev/podman-cluster-config.git|git@github.com:oriom-dev/podman-cluster-config.git) ;;
    *) fail "unexpected origin URL: $origin_url" ;;
  esac
  commit=$(git -C "$REPO_ROOT" rev-parse HEAD)
  remote_commit=$(live_main_commit)
  [[ $commit == "$remote_commit" ]] ||
    fail "local HEAD $commit is not live origin/main $remote_commit"
  printf '%s\n' "$commit"
}

build_system() {
  local system_path
  mkdir -p "$BUILD_DIR"
  note 'checking flake evaluation'
  nix --extra-experimental-features 'nix-command flakes' flake check \
    --no-update-lock-file --no-write-lock-file \
    "$REPO_ROOT" --no-build || fail 'flake check failed'
  note 'building kagoya-vps locally'
  system_path=$(nix --extra-experimental-features 'nix-command flakes' build \
    --no-update-lock-file --no-write-lock-file \
    --builders '' --print-out-paths --out-link "$RESULT_LINK" \
    "$REPO_ROOT#nixosConfigurations.kagoya-vps.config.system.build.toplevel") ||
    fail 'kagoya-vps build failed'
  [[ $system_path == /nix/store/* ]] || fail "unexpected build output: $system_path"
  [[ -x $system_path/bin/switch-to-configuration ]] ||
    fail "invalid NixOS system closure: $system_path"
  printf '%s\n' "$system_path"
}

run_remote() {
  local script=$1
  shift
  [[ -f $REMOTE_DIR/$script ]] || fail "missing remote command: $script"
  cat "$REMOTE_DIR/host.sh" "$REMOTE_DIR/$script" |
    ssh "${SSH_OPTIONS[@]}" "$VPS_TARGET" bash -s -- "$@"
}

copy_system() {
  local system_path=$1
  note "copying $system_path to $VPS_TARGET"
  NIX_SSHOPTS="$NIX_SSH_OPTIONS" \
    nix --extra-experimental-features 'nix-command flakes' \
    copy --to "ssh://$VPS_TARGET" "$system_path"
}

external_health() {
  local check_deployment=${1:-} pds_health appview_status
  pds_health=$(curl --fail --silent --show-error \
    --connect-timeout 5 --max-time 20 https://pds.oriom.dev/health) ||
    fail 'external PDS health check failed'
  grep -Eq '"ok"[[:space:]]*:[[:space:]]*true' <<< "$pds_health" ||
    fail 'external PDS health response is invalid'
  curl --fail --silent --show-error --output /dev/null \
    --connect-timeout 5 --max-time 20 \
    https://pds.oriom.dev/.well-known/mosimo/trust/snapshot.cbor ||
    fail 'external trust snapshot check failed'
  appview_status=$(curl --silent --show-error --output /dev/null \
    --write-out '%{http_code}' --connect-timeout 5 --max-time 20 \
    https://appview.oriom.dev/) || fail 'external AppView check failed'
  [[ $appview_status == 303 ]] || fail "unexpected AppView status: $appview_status"
  curl --fail --silent --show-error --output /dev/null \
    --connect-timeout 5 --max-time 20 https://mosimo.oriom.dev/ ||
    fail 'external Mosimo web check failed'
  if [[ $check_deployment == deployment ]]; then
    curl --fail --silent --show-error \
      --connect-timeout 5 --max-time 20 https://hello.oriom.dev/ |
      grep -Fxq 'hello from kagoya-vps' || fail 'external cluster hello check failed'

  fi
  note 'external health checks passed'
}
