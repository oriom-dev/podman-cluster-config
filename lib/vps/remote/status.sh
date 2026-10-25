#!/usr/bin/env bash

[[ $# -eq 0 ]] || fail 'status accepts no arguments'
acquire_remote_lock
rollback_system=unavailable
transaction=none
[[ -e $ROLLBACK_PROFILE ]] && rollback_system=$(readlink -e "$ROLLBACK_PROFILE")
[[ -e $TRANSACTION_FILE ]] && transaction=$(sed -n '1p' "$TRANSACTION_FILE")
if [[ -z $(git -C "$REPOSITORY" status --porcelain=v1 --untracked-files=all) ]]; then
  remote_tree=clean
else
  remote_tree=dirty
fi
printf 'remote_commit=%s\nremote_tree=%s\nactive_system=%s\npersistent_system=%s\nrollback_system=%s\ntransaction=%s\n' \
  "$(git -C "$REPOSITORY" rev-parse HEAD)" "$remote_tree" \
  "$(readlink -e /run/current-system)" "$(readlink -e /nix/var/nix/profiles/system)" \
  "$rollback_system" "$transaction"
nixos-version --json
systemctl show mosimo-pds mosimo-bsaf mosimo-bsaf-publisher \
  --property=Id,ActiveState,SubState,NRestarts,ExecStart
