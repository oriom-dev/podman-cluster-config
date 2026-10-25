#!/usr/bin/env bash

[[ $# -eq 0 ]] || fail 'recover accepts no arguments'
acquire_remote_lock
if [[ -e $TRANSACTION_FILE ]]; then
  restore_transaction
else
  verify_stable_system
fi
