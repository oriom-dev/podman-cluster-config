{ config, lib, ... }:
let
  cfg = config.services.omni-tcp-probe;
  port = 9682;
in
{
  # Temporary raw TCP diagnostic endpoint for checking whether external devices can
  # reach this host. It intentionally bypasses HTTP-only Caddy. See README.md.
  options.services.omni-tcp-probe.enable =
    lib.mkEnableOption "temporary public receive-only TCP probe on port ${toString port}";

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [ port ];
    cluster.containerPolicy.publicPortContainers = [ "omni-tcp-probe" ];

    virtualisation.oci-containers.containers.omni-tcp-probe = {
      image = "docker.io/library/python:3.13-alpine@sha256:1e1f6334529d1fb26a2ef619d7cffb30a7c7d7cc1cc7338ebee283a58d1aeaca";
      cmd = [ "python" "-u" "/app/probe.py" ];
      ports = [ "0.0.0.0:${toString port}:${toString port}/tcp" ];
      volumes = [ "${./probe.py}:/app/probe.py:ro" ];
      environment = {
        PYTHONDONTWRITEBYTECODE = "1";
        PYTHONUNBUFFERED = "1";
      };
      extraOptions = [
        "--read-only"
        "--user=65534:65534"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
        "--pids-limit=32"
        "--memory=64m"
        "--cpus=0.25"
        "--log-driver=journald"
      ];
    };

    systemd.services.podman-omni-tcp-probe.serviceConfig = {
      LogRateLimitIntervalSec = "30s";
      LogRateLimitBurst = 200;
    };
  };
}
