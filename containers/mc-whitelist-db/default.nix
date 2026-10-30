{ config, lib, ... }:
let
  cfg = config.services.mc-whitelist-db;
  podman = config.virtualisation.podman.package;
in
{
  options.services.mc-whitelist-db.enable = lib.mkEnableOption "Minecraft whitelist CockroachDB";

  config = lib.mkIf cfg.enable {
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
      image = "docker.io/cockroachdb/cockroach:v25.3.3@sha256:e6ba3582ae70f1da0cc28cbf82d2b180d307a492176f33df332983274230f643";
      environmentFiles = [ config.sops.secrets.mc-whitelist-db_env.path ];
      entrypoint = "/bin/sh";
      cmd = [ "/entrypoint.sh" ];
      volumes = [
        "${./entrypoint.sh}:/entrypoint.sh:ro"
        "mc-whitelist-db-data:/cockroach/cockroach-data"
      ];
      extraOptions = [
        "--network=mc-whitelist"
        "--network-alias=mc-whitelist-db.ts.home.arpa"
        "--security-opt=no-new-privileges"
        "--pids-limit=512"
        "--memory=768m"
        "--cpus=1"
        "--log-driver=journald"
      ];
    };

    systemd.services.podman-mc-whitelist-db = {
      requires = [ "podman-mc-whitelist-network.service" ];
      after = [ "podman-mc-whitelist-network.service" ];
    };
  };
}
