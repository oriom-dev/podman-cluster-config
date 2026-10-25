#!/usr/bin/env bash

test_deploy() {
  local expected_commit=$1 new_system=$2 old_system profile_system revision
  [[ ! -e $TRANSACTION_FILE ]] || fail 'another deployment transaction is active'
  [[ $expected_commit =~ ^[0-9a-f]{40}$ ]] || fail 'deploy requires a full Git commit ID'
  valid_system "$new_system" || fail "invalid NixOS system: $new_system"
  revision=$("$new_system/sw/bin/nixos-version" --configuration-revision)
  [[ $revision == "$expected_commit" ]] ||
    fail "system revision $revision does not match $expected_commit"
  validate_checkout "$expected_commit"
  old_system=$(readlink -e /run/current-system)
  profile_system=$(readlink -e /nix/var/nix/profiles/system)
  [[ $old_system == "$profile_system" ]] || fail 'active and persistent systems differ'
  [[ $old_system != "$new_system" ]] || fail 'requested system is already active'

  start_transaction deploy "$expected_commit" "$new_system" "$old_system"
  activate test "$new_system" || fail 'test activation failed'
  wait_for_health deployment || fail 'health checks failed after test activation'
  [[ $(readlink -e /run/current-system) == "$new_system" ]] || fail 'test system is not active'
  [[ $(readlink -e /nix/var/nix/profiles/system) == "$old_system" ]] ||
    fail 'test activation changed the persistent system'
  printf 'tested_commit=%s\ntested_system=%s\n' "$expected_commit" "$new_system"
}

expect_deploy() {
  local expected_commit=$1 expected_system=$2
  read_transaction
  [[ $TX_KIND == deploy ]] || fail 'active transaction is not a deployment'
  [[ $TX_COMMIT == "$expected_commit" ]] || fail 'deployment commit mismatch'
  [[ $TX_NEW_SYSTEM == "$expected_system" ]] || fail 'deployment system mismatch'
}

switch_deploy() {
  local expected_commit=$1 expected_system=$2
  expect_deploy "$expected_commit" "$expected_system"
  sudo -n true || fail 'passwordless sudo is unavailable'
  [[ $(readlink -e /run/current-system) == "$TX_NEW_SYSTEM" ]] || fail 'tested system is not active'
  [[ $(readlink -e /nix/var/nix/profiles/system) == "$TX_OLD_SYSTEM" ]] ||
    fail 'persistent system changed before switch'
  wait_for_health deployment || fail 'tested system is unhealthy on the fresh SSH connection'
  advance_checkout "$TX_COMMIT"
  activate switch "$TX_NEW_SYSTEM" || fail 'persistent switch failed'
  wait_for_health deployment || fail 'health checks failed after persistent switch'
  [[ $(readlink -e /run/current-system) == "$TX_NEW_SYSTEM" ]] || fail 'active system mismatch after switch'
  [[ $(readlink -e /nix/var/nix/profiles/system) == "$TX_NEW_SYSTEM" ]] ||
    fail 'persistent system mismatch after switch'
  printf 'switched_commit=%s\nswitched_system=%s\n' "$TX_COMMIT" "$TX_NEW_SYSTEM"
}

complete_deploy() {
  local expected_commit=$1 expected_system=$2
  expect_deploy "$expected_commit" "$expected_system"
  sudo -n true || fail 'passwordless sudo is unavailable'
  wait_for_health deployment || fail 'deployed system is unhealthy on the fresh SSH connection'
  [[ $(readlink -e /run/current-system) == "$TX_NEW_SYSTEM" ]] || fail 'active system mismatch'
  [[ $(readlink -e /nix/var/nix/profiles/system) == "$TX_NEW_SYSTEM" ]] ||
    fail 'persistent system mismatch'
  [[ $(git -C "$REPOSITORY" rev-parse HEAD) == "$TX_COMMIT" ]] || fail 'production checkout mismatch'
  set_profile "$ROLLBACK_PROFILE" "$TX_OLD_SYSTEM"
  clear_transaction "$TX_WATCHDOG"
  printf 'deployed_commit=%s\ndeployed_system=%s\nrollback_system=%s\n' \
    "$TX_COMMIT" "$TX_NEW_SYSTEM" "$TX_OLD_SYSTEM"
}

acquire_remote_lock
phase=${1:-}
shift || true
case "$phase" in
  test) [[ $# -eq 2 ]] || fail 'invalid deploy test arguments'; test_deploy "$1" "$2" ;;
  switch) [[ $# -eq 2 ]] || fail 'invalid deploy switch arguments'; switch_deploy "$1" "$2" ;;
  complete) [[ $# -eq 2 ]] || fail 'invalid deploy complete arguments'; complete_deploy "$1" "$2" ;;
  *) fail "unknown deploy phase: $phase" ;;
esac
