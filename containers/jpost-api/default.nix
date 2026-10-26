{ config, lib, ... }:
let
  cfg = config.services.jpost-api;
  image = "localhost/jpost-api:${builtins.hashFile "sha256" ./Containerfile}";
in
{
  options.services.jpost-api.enable = lib.mkEnableOption "JPost API proxy";

  config = lib.mkIf cfg.enable {
    sops.secrets.jpost-api_env = {
      sopsFile = ./secrets.yaml;
      format = "yaml";
      restartUnits = [ "podman-jpost-api.service" ];
    };

    virtualisation.oci-containers.containers.jpost-api = {
      inherit image;
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

    systemd.services.podman-jpost-api.preStart = ''
      ${config.virtualisation.podman.package}/bin/podman build \
        --tag ${lib.escapeShellArg image} \
        --file ${./Containerfile} ${./.}
    '';

    services.caddy.virtualHosts."jpost.oriom.dev".extraConfig = ''
      reverse_proxy 127.0.0.1:3002
    '';
  };
}
