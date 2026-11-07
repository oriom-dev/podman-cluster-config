# Encrypted backups for kagoya-vps persistent data (roadmap M1/M9C).
#
# SQLite databases are replicated with sqlite3_rsync and integrity-checked before
# restic stores them, so snapshots are application-consistent without stopping
# services. Local repositories cover corruption and mistakes; offsite.nix copies
# every snapshot to an append-only repository on home-desktop for host loss.
#
# Restore:  sudo restic-<job> snapshots / restore latest --target /tmp/restore
{ config, lib, pkgs, ... }:
let
  root = "/var/lib/backup";
  sqlite = "${pkgs.sqlite}/bin/sqlite3";
  rsync = "${pkgs.sqlite-rsync}/bin/sqlite3_rsync";
  podman = "${config.virtualisation.podman.package}/bin/podman";

  # Consistent replica of a live WAL-mode database, then verify it.
  # - `.backup` restarts whenever another process writes, so it never finished on
  #   the 16 GB HappyView database that ingests Jetstream continuously.
  # - VACUUM INTO finishes, but repacks every page, so each hourly PDS snapshot
  #   added ~80 MB to the repositories (fatal for the append-only off-host copy).
  # sqlite3_rsync copies one consistent snapshot and keeps the page layout, and the
  # replica persists between runs, so only changed pages are rewritten and restic
  # deduplicates the rest.
  snapshotSqlite = { src, dst, check ? "integrity_check" }: ''
    if ! ${rsync} ${src} ${dst}; then
      echo "sqlite3_rsync failed for ${dst}; rebuilding the replica" >&2
      rm -f ${dst}
      ${rsync} ${src} ${dst}
    fi
    result=$(${sqlite} ${dst} "PRAGMA ${check};")
    [ "$result" = ok ] || { echo "${check} failed for ${dst}: $result" >&2; exit 1; }
  '';

  mkJob = { name, prepare, extraPaths ? [ ], timer, prune }: {
    repository = "${root}/restic-${name}";
    passwordFile = config.sops.secrets.restic_password.path;
    initialize = true;
    paths = [ "${root}/staging-${name}" ] ++ extraPaths;
    backupPrepareCommand = ''
      set -eu
      install -d -m 0700 ${root}/staging-${name}
      ${prepare}
    '';
    # Staging is kept: the replicas are updated in place on the next run.
    timerConfig = timer;
    pruneOpts = prune;
  };
in
{
  imports = [ ./offsite.nix ];

  sops.secrets.restic_password = {
    sopsFile = ./secrets.yaml;
    format = "yaml";
    mode = "0400";
  };

  systemd.tmpfiles.rules = [ "d ${root} 0700 root root -" ];

  services.restic.backups = {
    # mosimo-pds holds user repositories and signing keys: RPO 1 h.
    pds = mkJob {
      name = "pds";
      prepare = snapshotSqlite {
        src = "/var/lib/private/mosimo-pds/pds.sqlite";
        dst = "${root}/staging-pds/pds.sqlite";
      };
      timer = { OnCalendar = "hourly"; RandomizedDelaySec = "5m"; Persistent = true; };
      prune = [ "--keep-hourly 48" "--keep-daily 14" "--keep-weekly 8" ];
    };

    # Everything else with RPO 24 h.
    daily = mkJob {
      name = "daily";
      prepare = lib.concatStrings [
        (snapshotSqlite {
          src = "/var/lib/containers/storage/volumes/happyview-data/_data/happyview.db";
          dst = "${root}/staging-daily/happyview.db";
          # 16 GB: the full integrity_check takes too long for a nightly job; the
          # weekly restore drill runs it on the restored copy.
          check = "quick_check";
        })
        (snapshotSqlite {
          src = "/var/lib/headscale/db.sqlite";
          dst = "${root}/staging-daily/headscale.sqlite";
        })
        # pg_dump runs inside the container over the local socket (trust auth).
        ''
          ${podman} exec mc-whitelist-db pg_dump -U whitelist_auth -d defaultdb \
            --format=custom > ${root}/staging-daily/mc-whitelist.pgdump
          [ -s ${root}/staging-daily/mc-whitelist.pgdump ]
        ''
      ];
      extraPaths = [
        "/var/lib/headscale/noise_private.key"
        "/var/lib/mosimo-importer"
        "/var/lib/mosimo-trust"
        "/var/lib/mosimo-deploy"
      ];
      timer = { OnCalendar = "*-*-* 03:30:00"; RandomizedDelaySec = "15m"; Persistent = true; };
      prune = [ "--keep-daily 7" "--keep-weekly 4" "--keep-monthly 6" ];
    };
  };

  # Keep backups from competing with live traffic on a 3 vCPU / 2.9 GiB host.
  systemd.services = lib.genAttrs [ "restic-backups-pds" "restic-backups-daily" ] (_: {
    serviceConfig = {
      Nice = 19;
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 7;
      MemoryHigh = "384M";
    };
  }) // {
    # Weekly restore drill: restore the latest snapshot of each job into a scratch
    # directory and run a full integrity check on every restored database.
    backup-restore-drill = {
      description = "Restore latest backups and verify database integrity";
      path = [ pkgs.restic pkgs.sqlite pkgs.postgresql_17 pkgs.coreutils pkgs.findutils ];
      environment.RESTIC_PASSWORD_FILE = config.sops.secrets.restic_password.path;
      serviceConfig = {
        Type = "oneshot";
        Nice = 19;
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 7;
        MemoryHigh = "384M";
      };
      script = ''
        set -eu
        scratch=$(mktemp -d ${root}/drill.XXXXXX)
        trap 'rm -rf "$scratch"' EXIT
        for job in pds daily; do
          repo=${root}/restic-$job
          restic -r "$repo" check
          restic -r "$repo" restore latest --target "$scratch/$job"
          count=0
          while IFS= read -r db; do
            result=$(sqlite3 "$db" "PRAGMA integrity_check;")
            [ "$result" = ok ] || { echo "integrity_check failed: $db: $result" >&2; exit 1; }
            count=$((count + 1))
          done < <(find "$scratch/$job" -type f \( -name '*.sqlite' -o -name '*.db' \))
          while IFS= read -r dump; do
            pg_restore --list "$dump" > /dev/null
            count=$((count + 1))
          done < <(find "$scratch/$job" -type f -name '*.pgdump')
          [ "$count" -gt 0 ] || { echo "no database restored from $job" >&2; exit 1; }
          echo "restore drill: $job ok ($count databases)"
          rm -rf "${scratch:?}/$job"
        done
      '';
    };
  };

  systemd.timers.backup-restore-drill = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "Sun 05:00"; RandomizedDelaySec = "30m"; Persistent = true; };
  };
}
