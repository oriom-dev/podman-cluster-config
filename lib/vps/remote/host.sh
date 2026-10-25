#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY=/home/operator/podman-cluster-config
readonly ROLLBACK_PROFILE=/nix/var/nix/profiles/oriom-deploy-rollback
readonly TRANSACTION_PROFILE=/nix/var/nix/profiles/oriom-deploy-transaction
readonly STATE_DIR=/home/operator/.local/state/oriom-vps
readonly TRANSACTION_FILE=/home/operator/.local/state/oriom-vps/transaction

TX_KIND=
TX_COMMIT=
TX_NEW_SYSTEM=
TX_OLD_SYSTEM=
TX_WATCHDOG=

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '==> %s\n' "$*" >&2
}

acquire_remote_lock() {
  mkdir -p "$STATE_DIR"
  exec 9>"$STATE_DIR/deploy.lock"
  flock -n 9 || fail 'another deployment operation is already running'
}

capture_diagnostics() {
  systemctl --failed --no-pager >&2 || true
  sudo -n journalctl -b --priority=warning --no-pager --lines=100 >&2 || true
}

health_once() {
  local check_deployment=${1:-} pds_health appview_status unit
  for unit in caddy headscale mosimo-pds mosimo-bsaf mosimo-bsaf-publisher podman-happyview; do
    systemctl is-active --quiet "$unit.service" || return 1
  done
  [[ -z $(systemctl --failed --no-legend --plain) ]] || return 1
  pds_health=$(curl --fail --silent --show-error \
    --connect-timeout 3 --max-time 5 https://pds.oriom.dev/health) || return 1
  grep -Eq '"ok"[[:space:]]*:[[:space:]]*true' <<< "$pds_health" || return 1
  curl --fail --silent --show-error --output /dev/null \
    --connect-timeout 3 --max-time 5 \
    https://pds.oriom.dev/.well-known/mosimo/trust/snapshot.cbor || return 1
  appview_status=$(curl --silent --show-error --output /dev/null \
    --write-out '%{http_code}' --connect-timeout 3 --max-time 5 \
    https://appview.oriom.dev/) || return 1
  [[ $appview_status == 303 ]] || return 1
  curl --fail --silent --show-error --output /dev/null \
    --connect-timeout 3 --max-time 5 https://mosimo.oriom.dev/ || return 1
  if [[ $check_deployment == deployment ]]; then
    for unit in podman-cluster-hello podman-jpost-api; do
      systemctl is-active --quiet "$unit.service" || return 1
    done
    curl --fail --silent --show-error \
      --connect-timeout 3 --max-time 5 http://127.0.0.1:3001/ |
      grep -Fxq 'hello from kagoya-vps' || return 1
    curl --fail --silent --show-error \
      --connect-timeout 3 --max-time 5 https://hello.oriom.dev/ |
      grep -Fxq 'hello from kagoya-vps' || return 1
    curl --fail --silent --show-error \
      --connect-timeout 3 --max-time 5 http://127.0.0.1:3002/health |
      grep -Fxq 'OK' || return 1
    curl --fail --silent --show-error \
      --connect-timeout 3 --max-time 5 https://jpost.oriom.dev/health |
      grep -Fxq 'OK' || return 1
  fi
}

wait_for_health() {
  local check_deployment=${1:-} attempts=6
  while (( attempts > 0 )); do
    if health_once "$check_deployment"; then
      note 'health checks passed'
      return 0
    fi
    attempts=$((attempts - 1))
    (( attempts > 0 )) && sleep 2
  done
  capture_diagnostics
  return 1
}

valid_system() {
  local system_path=$1
  [[ $system_path == /nix/store/*-nixos-system-kagoya-vps-* ]] || return 1
  [[ -x $system_path/bin/switch-to-configuration ]] || return 1
  [[ -x $system_path/sw/bin/nixos-version ]] || return 1
  nix-store --query "$system_path" >/dev/null || return 1
}

activate() {
  local action=$1 system_path=$2
  sudo -n timeout --signal=TERM --kill-after=30s 5m \
    nixos-rebuild "$action" --store-path "$system_path" --no-reexec
}

validate_checkout() {
  local expected_commit=$1 branch origin_url fetched_commit
  [[ -d $REPOSITORY/.git ]] || fail "missing production checkout: $REPOSITORY"
  [[ -z $(git -C "$REPOSITORY" status --porcelain=v1 --untracked-files=all) ]] ||
    fail 'production checkout is dirty'
  branch=$(git -C "$REPOSITORY" symbolic-ref --quiet --short HEAD) ||
    fail 'production checkout is detached'
  [[ $branch == main ]] || fail "production checkout must use main, found $branch"
  origin_url=$(git -C "$REPOSITORY" remote get-url origin)
  [[ $origin_url == https://github.com/oriom-dev/podman-cluster-config.git ]] ||
    fail "unexpected production origin: $origin_url"
  timeout 90s git -C "$REPOSITORY" fetch --no-tags \
    origin refs/heads/main:refs/remotes/origin/main
  fetched_commit=$(git -C "$REPOSITORY" rev-parse origin/main)
  [[ $fetched_commit == "$expected_commit" ]] ||
    fail "origin/main is $fetched_commit, expected $expected_commit"
  git -C "$REPOSITORY" merge-base --is-ancestor HEAD "$expected_commit" ||
    fail 'production checkout cannot fast-forward to the requested commit'
}

advance_checkout() {
  local expected_commit=$1
  validate_checkout "$expected_commit"
  git -C "$REPOSITORY" merge --ff-only origin/main
  [[ $(git -C "$REPOSITORY" rev-parse HEAD) == "$expected_commit" ]] ||
    fail 'production checkout HEAD mismatch'
}

set_profile() {
  local profile=$1 system_path=$2
  sudo -n nix-env --profile "$profile" --set "$system_path"
  [[ $(readlink -e "$profile") == "$system_path" ]] || fail "failed to set profile $profile"
}

clear_transaction_profile() {
  sudo -n rm -f "$TRANSACTION_PROFILE"
  sudo -n find /nix/var/nix/profiles -maxdepth 1 \
    -name 'oriom-deploy-transaction-*-link' -delete
}

write_transaction() {
  local kind=$1 commit=$2 new_system=$3 old_system=$4 watchdog=$5
  umask 077
  printf '%s\n%s\n%s\n%s\n%s\n' \
    "$kind" "$commit" "$new_system" "$old_system" "$watchdog" > "$TRANSACTION_FILE.tmp"
  mv "$TRANSACTION_FILE.tmp" "$TRANSACTION_FILE"
}

read_transaction() {
  local -a values
  [[ -f $TRANSACTION_FILE ]] || fail 'no deployment transaction is active'
  mapfile -t values < "$TRANSACTION_FILE"
  [[ ${#values[@]} -eq 5 ]] || fail 'deployment transaction is corrupt'
  TX_KIND=${values[0]}
  TX_COMMIT=${values[1]}
  TX_NEW_SYSTEM=${values[2]}
  TX_OLD_SYSTEM=${values[3]}
  TX_WATCHDOG=${values[4]}
  [[ $TX_KIND == deploy || $TX_KIND == rollback ]] || fail 'invalid transaction kind'
  valid_system "$TX_NEW_SYSTEM" || fail 'invalid transaction target system'
  valid_system "$TX_OLD_SYSTEM" || fail 'invalid transaction restore system'
  [[ $TX_WATCHDOG == oriom-vps-recovery-* ]] || fail 'invalid transaction watchdog'
}

cancel_watchdog() {
  local watchdog=$1
  sudo -n systemctl stop "$watchdog.timer" "$watchdog.service" >/dev/null 2>&1 || true
  if sudo -n systemctl is-active --quiet "$watchdog.timer" ||
    sudo -n systemctl is-active --quiet "$watchdog.service"; then
    return 1
  fi
  sudo -n systemctl reset-failed "$watchdog.timer" "$watchdog.service" >/dev/null 2>&1 || true
}

clear_transaction() {
  local watchdog=$1
  cancel_watchdog "$watchdog" || fail 'failed to stop the automatic recovery timer'
  clear_transaction_profile
  rm -f "$TRANSACTION_FILE.tmp"
  rm -f "$TRANSACTION_FILE"
}

start_transaction() {
  local kind=$1 commit=$2 new_system=$3 old_system=$4 watchdog
  watchdog="oriom-vps-recovery-$(date +%s)-$$"
  set_profile "$TRANSACTION_PROFILE" "$old_system"
  write_transaction "$kind" "$commit" "$new_system" "$old_system" "$watchdog"
  if ! sudo -n systemd-run --quiet --unit="$watchdog" --on-active=30m \
    --timer-property=AccuracySec=1s \
    "$old_system/sw/bin/nixos-rebuild" switch --store-path "$old_system" --no-reexec; then
    clear_transaction_profile
    rm -f "$TRANSACTION_FILE"
    fail 'failed to arm the automatic recovery timer'
  fi
}

restore_transaction() {
  local kind old_system watchdog
  read_transaction
  kind=$TX_KIND
  old_system=$TX_OLD_SYSTEM
  watchdog=$TX_WATCHDOG
  note "restoring $old_system"
  activate switch "$old_system" || fail 'system restoration failed; watchdog remains armed'
  wait_for_health || fail 'restored system is unhealthy; watchdog remains armed'
  [[ $(readlink -e /run/current-system) == "$old_system" ]] || fail 'active system was not restored'
  [[ $(readlink -e /nix/var/nix/profiles/system) == "$old_system" ]] ||
    fail 'persistent system was not restored'
  clear_transaction "$watchdog"
  printf 'recovered_transaction=%s\nrestored_system=%s\n' "$kind" "$old_system"
}

verify_stable_system() {
  local active_system profile_system
  active_system=$(readlink -e /run/current-system)
  profile_system=$(readlink -e /nix/var/nix/profiles/system)
  [[ $active_system == "$profile_system" ]] || fail 'active and persistent systems differ'
  wait_for_health || fail 'active system is unhealthy'
  printf 'transaction=none\nstable_system=%s\n' "$active_system"
}
