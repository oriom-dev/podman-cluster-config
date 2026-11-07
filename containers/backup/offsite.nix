# Off-host copy: pushes every local snapshot to the append-only restic REST server
# on home-desktop over the tailnet (containers/backup-receiver).
#
# home-desktop is a lower-trust node that may be offline. An unreachable receiver is
# logged and tolerated, so it does not leave a failed unit (which would also block
# deployments). The job fails only when the last successful copy is older than
# 48 hours, i.e. when the off-host RPO is actually violated.
{ config, pkgs, ... }:
let
  root = "/var/lib/backup";
  receiver = "100.64.0.2:8000"; # home-desktop (tag:worker), stable Headscale address
  user = "kagoya-vps";
  maxAgeSeconds = 48 * 3600;
  stamp = "${root}/offsite-last-success";
in
{
  sops.secrets.offsite_rest_password = {
    sopsFile = ./secrets.yaml;
    format = "yaml";
    mode = "0400";
  };

  systemd.services.backup-offsite = {
    description = "Copy restic snapshots to home-desktop";
    after = [ "tailscaled.service" ];
    path = [ pkgs.restic pkgs.coreutils pkgs.bash ];
    environment = {
      RESTIC_PASSWORD_FILE = config.sops.secrets.restic_password.path;
      RESTIC_REST_USERNAME = user;
      RESTIC_CACHE_DIR = "/var/cache/backup-offsite";
    };
    serviceConfig = {
      Type = "oneshot";
      CacheDirectory = "backup-offsite";
      Nice = 19;
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 7;
      MemoryHigh = "384M";
    };
    script = ''
      set -eu
      RESTIC_REST_PASSWORD=$(cat ${config.sops.secrets.offsite_rest_password.path})
      export RESTIC_REST_PASSWORD
      now=$(date +%s)
      last=$(cat ${stamp} 2>/dev/null || echo 0)
      age=$(( now - last ))

      if ! timeout 10 bash -c 'exec 3<>/dev/tcp/${builtins.replaceStrings [ ":" ] [ "/" ] receiver}' 2>/dev/null; then
        if (( age > ${toString maxAgeSeconds} )); then
          echo "receiver ${receiver} unreachable; last successful copy $(( age / 3600 )) h ago exceeds the 48 h RPO" >&2
          exit 1
        fi
        echo "receiver ${receiver} unreachable; last successful copy $(( age / 3600 )) h ago, within the 48 h RPO"
        exit 0
      fi

      for job in pds daily; do
        src=${root}/restic-$job
        dst=rest:http://${receiver}/${user}/$job
        if ! restic -r "$dst" cat config > /dev/null 2>&1; then
          # Same chunker parameters keep deduplication across the two repositories.
          restic -r "$dst" init --from-repo "$src" \
            --from-password-file "$RESTIC_PASSWORD_FILE" --copy-chunker-params
        fi
        restic -r "$dst" copy --from-repo "$src" \
          --from-password-file "$RESTIC_PASSWORD_FILE" --retry-lock 30m
      done
      date +%s > ${stamp}
    '';
  };

  systemd.timers.backup-offsite = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # After the hourly pds snapshot (hourly + up to 5 min) has finished.
      OnCalendar = "*-*-* *:20:00";
      RandomizedDelaySec = "5m";
      Persistent = true;
    };
  };
}
