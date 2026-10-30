{ config, lib, ... }:
let
  cfg = config.services.mc-whitelist-auth;
  image = "localhost/mc-whitelist-auth:${builtins.hashFile "sha256" ./Containerfile}";
in
{
  imports = [ ../mc-whitelist-db ];

  options.services.mc-whitelist-auth.enable = lib.mkEnableOption "Minecraft whitelist authentication";

  config = lib.mkIf cfg.enable {
    services.mc-whitelist-db.enable = true;

    sops.secrets.mc-whitelist-auth_env = {
      sopsFile = ./secrets.yaml;
      format = "yaml";
      mode = "0400";
      restartUnits = [ "podman-mc-whitelist-auth.service" ];
    };

    virtualisation.oci-containers.containers.mc-whitelist-auth = {
      inherit image;
      pull = "never";
      dependsOn = [ "mc-whitelist-db" ];
      environment = {
        PORT = "3000";
        PUBLIC_BASE_URL = "https://mc.oriom.dev";
        BETTER_AUTH_URL = "https://mc.oriom.dev";
      };
      environmentFiles = [ config.sops.secrets.mc-whitelist-auth_env.path ];
      ports = [ "127.0.0.1:3003:3000" ];
      extraOptions = [
        "--init"
        "--network=mc-whitelist"
        "--network-alias=mc-whitelist-auth.ts.home.arpa"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
        "--pids-limit=192"
        "--memory=384m"
        "--cpus=0.75"
        "--log-driver=journald"
      ];
    };

    systemd.services.podman-mc-whitelist-auth.preStart = ''
      ${config.virtualisation.podman.package}/bin/podman build \
        --tag ${lib.escapeShellArg image} \
        --file ${./Containerfile} ${./.}
    '';

    services.caddy.virtualHosts."mc.oriom.dev".extraConfig = ''
      @internal_api path /api/v1/*
      respond @internal_api "Forbidden" 403

      reverse_proxy 127.0.0.1:3003
    '';
  };
}
