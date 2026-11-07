# Restarts HappyView when its Jetstream subscription goes silent.
#
# HappyView 2.16.0 has no read timeout on the Jetstream WebSocket. On 2026-10-27 the
# connection went half-open without a disconnect, and ingestion stopped for 11 days
# until an unrelated restart. Jetstream normally delivers identity/account events
# every few seconds plus a server ping every 30 s, so minutes of silence reliably
# mean a dead stream.
{ config, lib, pkgs, ... }:
let
  unit = "podman-happyview.service";
  silenceSeconds = 300;
  minRestartIntervalSeconds = 900;
  stateFile = "/var/lib/happyview-jetstream-watchdog/last-restart";
in
lib.mkIf config.services.happyview.enable {
  # The watchdog reads these debug lines; pin the filter so a HappyView default change
  # cannot silently turn every check into a restart. Per-request tower_http debug
  # lines are dropped to keep the journal small.
  virtualisation.oci-containers.containers.happyview.environment.RUST_LOG =
    "happyview=info,happyview::jetstream=debug,tower_http=info,sqlx=warn";

  systemd.services.happyview-jetstream-watchdog = {
    description = "Restart HappyView when Jetstream ingestion stalls";
    after = [ unit ];
    path = [ config.systemd.package pkgs.coreutils pkgs.gnugrep ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "happyview-jetstream-watchdog";
    };
    script = ''
      systemctl is-active --quiet ${unit} || exit 0

      now=$(date +%s)
      started_us=$(systemctl show -P ActiveEnterTimestampMonotonic ${unit})
      uptime_s=$(( $(cut -d. -f1 /proc/uptime) - started_us / 1000000 ))
      (( uptime_s >= ${toString silenceSeconds} )) || exit 0

      if journalctl -u ${unit} --since "-${toString silenceSeconds}s" -o cat --no-pager |
        grep -q 'happyview::jetstream'; then
        exit 0
      fi

      last=$(cat ${stateFile} 2>/dev/null || echo 0)
      if (( now - last < ${toString minRestartIntervalSeconds} )); then
        echo "jetstream silent for ${toString silenceSeconds}s, but restarted $(( now - last ))s ago; waiting" >&2
        exit 0
      fi

      echo "jetstream silent for ${toString silenceSeconds}s; restarting ${unit}" >&2
      echo "$now" > ${stateFile}
      systemctl restart ${unit}
    '';
  };

  systemd.timers.happyview-jetstream-watchdog = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "2min";
    };
  };
}
