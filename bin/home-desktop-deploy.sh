#!/usr/bin/env bash
# Deploys the reviewed GitHub main to the home-desktop VM (roadmap M4 short command).
#
#   ./bin/home-desktop-deploy.sh            test-activate, health-check, then switch
#   ./bin/home-desktop-deploy.sh status     show revision and health only
#
# The VM is reached through desktop-1 (hosts/home_desktop/ssh_config). A failed
# health check after test activation restores the running system from the boot
# profile, which `test` does not change.
set -euo pipefail

repo=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
ssh_config=$repo/hosts/home_desktop/ssh_config
[[ -f $ssh_config ]] || { echo "missing $ssh_config (see hosts/home_desktop/README.md)" >&2; exit 1; }
export NIX_SSHOPTS="-F $ssh_config"
remote() { ssh -F "$ssh_config" -o BatchMode=yes home-desktop "$@"; }
note() { printf '==> %s\n' "$*" >&2; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# shellcheck disable=SC2016  # expanded on the VM, not locally
health() {
  remote '
    set -u
    state=$(systemctl is-system-running 2>/dev/null || true)
    failed=$(systemctl --failed --no-legend --plain | awk "{print \$1}" | tr "\n" " ")
    ts=$(tailscale status --json 2>/dev/null | grep -o "\"Online\": *true" | head -1)
    rest=$(systemctl is-active restic-rest-server.socket)
    data=$(findmnt -n -o TARGET /srv/data || true)
    printf "revision=%s\nsystem=%s\nfailed=%s\ntailscale=%s\nrest-server=%s\ndata=%s\n" \
      "$(nixos-version --configuration-revision 2>/dev/null)" "$state" "${failed:-none}" \
      "${ts:+online}" "$rest" "${data:-missing}"
    [ "$state" = running ] && [ -n "$ts" ] && [ "$rest" = active ] && [ -n "$data" ]
  '
}

if [[ ${1:-} == status ]]; then
  health
  exit
fi

[[ -z $(git -C "$repo" status --porcelain=v1 --untracked-files=all) ]] || fail 'deploy requires a clean working tree'
commit=$(git -C "$repo" rev-parse HEAD)
live=$(git -C "$repo" ls-remote https://github.com/oriom-dev/podman-cluster-config.git refs/heads/main | cut -f1)
[[ $commit == "$live" ]] || fail "local HEAD $commit is not live origin/main $live"

rebuild=(nix shell --inputs-from "$repo" nixpkgs#nixos-rebuild-ng --command nixos-rebuild)
target=(--flake "$repo#home-desktop" --target-host home-desktop --sudo --no-reexec)

note "test-activating $commit"
"${rebuild[@]}" test "${target[@]}"

note 'health check'
for _ in $(seq 30); do
  if health > /dev/null 2>&1; then break; fi
  sleep 2
done
if ! health; then
  note 'unhealthy: restoring the boot profile'
  remote 'sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch'
  fail 'deployment rolled back'
fi

note 'switching boot profile'
"${rebuild[@]}" switch "${target[@]}"
health
note "deployed $commit"
