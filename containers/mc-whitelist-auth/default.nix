{ config, lib, ... }:
let
  cfg = config.services.mc-whitelist-auth;
  localImage = import ../../lib/local-image.nix {
    inherit lib;
    podman = config.virtualisation.podman.package;
  } {
    name = "mc-whitelist-auth";
    # Only files the Containerfile copies; edits elsewhere must not rebuild the image.
    context = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [ ./Containerfile ./src-old ];
    };
  };
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
      inherit (localImage) image;
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

    systemd.services.podman-mc-whitelist-auth.preStart = localImage.preStart;

    services.caddy.virtualHosts."mc.oriom.dev".extraConfig = ''
      @internal_api path /api/v1/*
      respond @internal_api "Forbidden" 403

      reverse_proxy 127.0.0.1:3003
    '';
  };
}
