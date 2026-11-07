{ config, lib, ... }:
let
  cfg = config.services.jpost-api;
  localImage = import ../../lib/local-image.nix {
    inherit lib;
    podman = config.virtualisation.podman.package;
  } {
    name = "jpost-api";
    # Only files the Containerfile copies; edits elsewhere must not rebuild the image.
    context = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [ ./Containerfile ./src ];
    };
  };
in
{
  options.services.jpost-api.enable = lib.mkEnableOption "JPost API proxy";

  config = lib.mkIf cfg.enable {
    sops.secrets.jpost-api_env = {
      sopsFile = ./secrets.yaml;
      format = "yaml";
      mode = "0400";
      restartUnits = [ "podman-jpost-api.service" ];
    };

    virtualisation.oci-containers.containers.jpost-api = {
      inherit (localImage) image;
      pull = "never";
      environmentFiles = [ config.sops.secrets.jpost-api_env.path ];
      ports = [ "127.0.0.1:3002:8080" ];
      extraOptions = [
        "--init"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
        "--pids-limit=128"
        "--memory=192m"
        "--cpus=0.5"
        "--log-driver=journald"
      ];
    };

    systemd.services.podman-jpost-api.preStart = localImage.preStart;

    services.caddy.virtualHosts."jpost.oriom.dev".extraConfig = ''
      reverse_proxy 127.0.0.1:3002
    '';
  };
}
