#!/usr/bin/env bash
# Compares the firewall declared in the evaluated kagoya-vps config with the sockets
# actually listening on the VPS (roadmap M1 port matrix). Read-only on the host.
#
#   public    non-loopback listener on a firewall-open port (intended exposure)
#   bridge    Podman bridge DNS (aardvark-dns), reachable only from containers
#   loopback  127.0.0.0/8 or ::1; reachable only from the host (Caddy upstreams etc.)
#   SHADOW    non-loopback listener on a firewall-closed port: protected only by
#             the firewall, so bind it to loopback instead
#   STALE     firewall-open port with no listener: close it
set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/vps/client.sh"
enter_vps_environment "${BASH_SOURCE[0]}" "$@"
[[ $# -ge 1 ]] || fail 'usage: vps-port-audit.sh TARGET [SSH_OPTION...]'
configure_vps "$@"
require_local_environment

note 'evaluating declared firewall'
declared=$(nix --extra-experimental-features 'nix-command flakes' eval --raw \
  --no-update-lock-file --no-write-lock-file \
  "$REPO_ROOT#nixosConfigurations.kagoya-vps.config.networking.firewall" \
  --apply 'f: builtins.concatStringsSep "\n"
    ((map (p: "tcp ${toString p}") f.allowedTCPPorts)
     ++ (map (p: "udp ${toString p}") f.allowedUDPPorts))') ||
  fail 'failed to evaluate the firewall'

note 'reading listeners on the VPS'
live=$(ssh "${SSH_OPTIONS[@]}" "$VPS_TARGET" ss -Hltnu |
  awk '{print $1, $5}' | sort -u) || fail 'failed to read listeners'

bridge_cidrs=$(ssh "${SSH_OPTIONS[@]}" "$VPS_TARGET" ip -br -4 addr show type bridge |
  awk '{print $3}' | cut -d/ -f1)

problems=0
printf '%-6s %-28s %s\n' PROTO LISTEN CLASS
while read -r proto addr; do
  [[ -n $proto ]] || continue
  port=${addr##*:}
  host=${addr%:*}
  host=${host#[}; host=${host%]}
  host=${host%%%*}
  if [[ $host == 127.* || $host == ::1 ]]; then
    class=loopback
  elif grep -qxF "$host" <<<"$bridge_cidrs" && [[ $port == 53 ]]; then
    class=bridge
  elif grep -qxF "$proto $port" <<<"$declared"; then
    class=public
  else
    class=SHADOW
    problems=1
  fi
  printf '%-6s %-28s %s\n' "$proto" "$addr" "$class"
done <<<"$live"

while read -r proto port; do
  [[ -n $proto ]] || continue
  if ! awk -v p="$proto" -v n="$port" '$1 == p && $2 ~ ":" n "$" && $2 !~ /^(127\.|\[::1\])/ {found=1} END {exit !found}' <<<"$live"; then
    printf '%-6s %-28s %s\n' "$proto" "*:$port" STALE
    problems=1
  fi
done <<<"$declared"

(( problems == 0 )) || fail 'port audit found SHADOW or STALE entries'
note 'port audit passed'
