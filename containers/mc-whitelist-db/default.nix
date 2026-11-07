# PostgreSQL for mc-whitelist-auth.
#
# Replaced a single-node CockroachDB (2026-11-07) that used ~600 MB RAM and 2.2 GB
# disk for empty tables. The app speaks plain PostgreSQL (pg + Kysely) and creates
# its schema on start, so no data was migrated. The old `mc-whitelist-db-data`
# volume is left untouched for rollback; remove it once this is settled.
#
# Only containers on the `mc-whitelist` network can reach the database; nothing is
# published on the host. Traffic stays on that single-host bridge, so TLS is off.
{ config, lib, ... }:
let
  cfg = config.services.mc-whitelist-db;
  podman = config.virtualisation.podman.package;
in
{
  options.services.mc-whitelist-db.enable = lib.mkEnableOption "Minecraft whitelist PostgreSQL";

  config = lib.mkIf cfg.enable {
    # POSTGRES_PASSWORD=<same password as in mc-whitelist-auth's DB_URL>. It is only
    # applied when the volume is first initialised; rotate with ALTER ROLE.
    sops.secrets.mc-whitelist-db_env = {
      sopsFile = ./secrets.yaml;
      format = "yaml";
      mode = "0400";
      restartUnits = [ "podman-mc-whitelist-db.service" ];
    };

    systemd.services.podman-mc-whitelist-network = {
      description = "Podman network for Minecraft whitelist services";
      before = [ "podman-mc-whitelist-db.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${podman}/bin/podman network exists mc-whitelist ||
          ${podman}/bin/podman network create mc-whitelist
      '';
    };

    virtualisation.oci-containers.containers.mc-whitelist-db = {
      image = "docker.io/library/postgres:17-alpine@sha256:3540c0362c809df084ffac0ae69fe794515f9de92692f02178bcdce0ef0302ac";
      environment = {
        POSTGRES_USER = "whitelist_auth";
        POSTGRES_DB = "defaultdb";
      };
      environmentFiles = [ config.sops.secrets.mc-whitelist-db_env.path ];
      cmd = [
        "postgres"
        "-c" "shared_buffers=32MB"
        "-c" "max_connections=20"
        "-c" "listen_addresses=*"
      ];
      # `:U` hands the volume to the image's postgres user (uid 70).
      volumes = [ "mc-whitelist-pg-data:/var/lib/postgresql/data:U" ];
      extraOptions = [
        "--network=mc-whitelist"
        "--network-alias=mc-whitelist-db.ts.home.arpa"
        "--user=70:70"
        "--read-only"
        "--tmpfs=/var/run/postgresql:rw,mode=1777"
        "--tmpfs=/tmp:rw,mode=1777"
        "--shm-size=64m"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
        "--pids-limit=128"
        "--memory=256m"
        "--cpus=0.5"
        "--log-driver=journald"
        "--health-cmd=pg_isready -U whitelist_auth -d defaultdb"
        "--health-interval=30s"
      ];
    };

    systemd.services.podman-mc-whitelist-db = {
      requires = [ "podman-mc-whitelist-network.service" ];
      after = [ "podman-mc-whitelist-network.service" ];
    };
  };
}
