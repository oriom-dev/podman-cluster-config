{ config, lib, ... }:
let
  cfg = config.services.cluster-hello;
in
{
  # Minimal container example. Copy this directory to add a service.
  options.services.cluster-hello.enable = lib.mkEnableOption "hello.oriom.dev echo service";

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.cluster-hello = {
      # Pin by digest: the tag documents intent, the digest decides what runs.
      image = "docker.io/hashicorp/http-echo:1.0@sha256:fcb75f691c8b0414d670ae570240cbf95502cc18a9ba57e982ecac589760a186";
      cmd = [ "-listen=:5678" "-text=hello from ${config.networking.hostName}" ];
      # Image already runs as uid 65532. Loopback only; Caddy is the public entry point.
      ports = [ "127.0.0.1:3001:5678" ];
      extraOptions = [
        "--read-only"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
        "--pids-limit=32"
        "--memory=32m"
        "--cpus=0.25"
        "--log-driver=journald"
      ];
    };

    services.caddy.virtualHosts."hello.oriom.dev".extraConfig = ''
      reverse_proxy 127.0.0.1:3001
    '';
  };
}
