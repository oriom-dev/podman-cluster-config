{ ... }:
{
  # Temporary raw TCP diagnostic endpoint; intentionally bypasses HTTP-only Caddy.
  networking.firewall.allowedTCPPorts = [ 9682 ];

  virtualisation.oci-containers.containers.omni-tcp-probe = {
    image = "docker.io/library/python:3.13-alpine";
    cmd = [ "python" "-u" "/app/probe.py" ];
    ports = [ "0.0.0.0:9682:9682/tcp" ];
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
}
