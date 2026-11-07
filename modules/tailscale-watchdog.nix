# Recovers tailscaled when its control-plane connection is stuck on a dead TCP flow.
#
# Seen on home-desktop (2026-11-07): after a two-minute network loss, WinNAT had
# dropped the mapping of tailscaled's long-lived connection to Headscale. Its
# retransmits reached kagoya-vps from a new source port and were silently dropped
# as invalid, so the node stayed "offline" to the coordination server for 10+
# minutes while the kernel kept retrying the dead socket.
#
# 1. tcp_retries2 = 8 gives up on an unacknowledged connection after ~100 s instead
#    of ~15 min (default 15), so clients reconnect on their own.
# 2. If the node is still not connected to the coordination server after 5 minutes,
#    the watchdog restarts tailscaled (at most once per 15 minutes). Nodes that were
#    never enrolled (NeedsLogin) are left alone.
{ config, lib, pkgs, ... }:
let
  offlineSeconds = 300;
  minRestartIntervalSeconds = 900;
  state = "/run/tailscale-watchdog";
in
{
  boot.kernel.sysctl."net.ipv4.tcp_retries2" = 8;

  systemd.services.tailscale-watchdog = lib.mkIf config.services.tailscale.enable {
    description = "Restart tailscaled when it loses the coordination server";
    after = [ "tailscaled.service" ];
    path = [ config.services.tailscale.package pkgs.jq pkgs.coreutils config.systemd.package ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu
      mkdir -p ${state}
      now=$(date +%s)
      status=$(tailscale status --json 2>/dev/null || echo '{}')
      backend=$(jq -r '.BackendState // "unknown"' <<<"$status")
      online=$(jq -r '.Self.Online // false' <<<"$status")

      if [ "$backend" != Running ] || [ "$online" = true ]; then
        rm -f ${state}/offline-since
        exit 0
      fi

      [ -f ${state}/offline-since ] || echo "$now" > ${state}/offline-since
      since=$(cat ${state}/offline-since)
      (( now - since >= ${toString offlineSeconds} )) || exit 0

      last=$(cat ${state}/last-restart 2>/dev/null || echo 0)
      if (( now - last < ${toString minRestartIntervalSeconds} )); then
        echo "offline for $(( now - since ))s; restarted $(( now - last ))s ago, waiting" >&2
        exit 0
      fi
      echo "not connected to the coordination server for $(( now - since ))s; restarting tailscaled" >&2
      echo "$now" > ${state}/last-restart
      rm -f ${state}/offline-since
      systemctl restart tailscaled.service
    '';
  };

  systemd.timers.tailscale-watchdog = lib.mkIf config.services.tailscale.enable {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1min";
    };
  };
}
