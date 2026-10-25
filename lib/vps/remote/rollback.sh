#!/usr/bin/env bash

test_rollback() {
  local current_system profile_system target_system
  [[ ! -e $TRANSACTION_FILE ]] || fail 'another deployment transaction is active'
  current_system=$(readlink -e /run/current-system)
  profile_system=$(readlink -e /nix/var/nix/profiles/system)
  [[ $current_system == "$profile_system" ]] || fail 'active and persistent systems differ'
  [[ -e $ROLLBACK_PROFILE ]] || fail 'no retained rollback system exists'
  target_system=$(readlink -e "$ROLLBACK_PROFILE")
  valid_system "$target_system" || fail 'retained rollback system is invalid'
  [[ $target_system != "$current_system" ]] || fail 'rollback system is already active'

  start_transaction rollback - "$target_system" "$current_system"
  activate test "$target_system" || fail 'rollback test activation failed'
  wait_for_health || fail 'rollback target failed health checks'
  [[ $(readlink -e /run/current-system) == "$target_system" ]] || fail 'rollback test system is not active'
  [[ $(readlink -e /nix/var/nix/profiles/system) == "$current_system" ]] ||
    fail 'rollback test changed the persistent system'
  printf 'tested_system=%s\nreturn_system=%s\n' "$target_system" "$current_system"
}

expect_rollback() {
  read_transaction
  [[ $TX_KIND == rollback ]] || fail 'active transaction is not a rollback'
}

switch_rollback() {
  expect_rollback
  sudo -n true || fail 'passwordless sudo is unavailable'
  [[ $(readlink -e /run/current-system) == "$TX_NEW_SYSTEM" ]] || fail 'tested rollback system is not active'
  [[ $(readlink -e /nix/var/nix/profiles/system) == "$TX_OLD_SYSTEM" ]] ||
    fail 'persistent system changed before rollback switch'
  wait_for_health || fail 'rollback target is unhealthy on the fresh SSH connection'
  activate switch "$TX_NEW_SYSTEM" || fail 'rollback switch failed'
  wait_for_health || fail 'health checks failed after rollback switch'
  [[ $(readlink -e /run/current-system) == "$TX_NEW_SYSTEM" ]] || fail 'active system mismatch after rollback'
  [[ $(readlink -e /nix/var/nix/profiles/system) == "$TX_NEW_SYSTEM" ]] ||
    fail 'persistent system mismatch after rollback'
  printf 'switched_system=%s\nreturn_system=%s\n' "$TX_NEW_SYSTEM" "$TX_OLD_SYSTEM"
}

complete_rollback() {
  expect_rollback
  sudo -n true || fail 'passwordless sudo is unavailable'
  wait_for_health || fail 'rollback system is unhealthy on the fresh SSH connection'
  [[ $(readlink -e /run/current-system) == "$TX_NEW_SYSTEM" ]] || fail 'active system mismatch'
  [[ $(readlink -e /nix/var/nix/profiles/system) == "$TX_NEW_SYSTEM" ]] ||
    fail 'persistent system mismatch'
  set_profile "$ROLLBACK_PROFILE" "$TX_OLD_SYSTEM"
  clear_transaction "$TX_WATCHDOG"
  printf 'active_system=%s\nrollback_system=%s\n' "$TX_NEW_SYSTEM" "$TX_OLD_SYSTEM"
}

acquire_remote_lock
phase=${1:-}
shift || true
case "$phase" in
  test) [[ $# -eq 0 ]] || fail 'rollback test accepts no arguments'; test_rollback ;;
  switch) [[ $# -eq 0 ]] || fail 'rollback switch accepts no arguments'; switch_rollback ;;
  complete) [[ $# -eq 0 ]] || fail 'rollback complete accepts no arguments'; complete_rollback ;;
  *) fail "unknown rollback phase: $phase" ;;
esac
