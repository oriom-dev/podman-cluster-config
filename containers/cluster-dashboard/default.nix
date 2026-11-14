# Cluster resource dashboard (see README.md).
#
# - agent (every node, native): read-only metrics of the node, its Podman containers
#   and native services. Socket-activated on /run/cluster-agent/agent.sock; with
#   `agent.listenTailnet` also on tailscale0:9925 so the collector can pull it. The
#   Headscale ACL lets only tag:ingress reach that port.
# - dashboard (one node): the local agent also collects every tailnet peer, and a
#   container serves the UI from that Unix socket. It has no other host access.
# - tailscale sidecar: a userspace tailscaled in the dashboard's network namespace
#   joins the operator's Tailscale tailnet (not Headscale) as a tagged node and hosts
#   the Tailscale Service `svc:dashboard`. Who may connect is decided by that
#   tailnet's policy (tag:host and tag:mobile). Nothing is published publicly.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.cluster-dashboard;
  agentPort = 9925;
  uiPort = 3010;
  # Not /run/cluster-dashboard: oci-containers owns that as the container's RuntimeDirectory
  # and systemd recreates it (deleting the socket) whenever the container restarts.
  # switch-to-configuration never restarts a changed .socket unit, so moving the socket
  # also needs a new unit name (cluster-agent replaced cluster-dashboard-agent).
  socketDir = "/run/cluster-agent";
  gid = 29925; # shared by the agent socket and the dashboard container's user
  podman = config.virtualisation.podman.package;

  # HTTPS on 443: tailscaled terminates TLS with the Service's Let's Encrypt certificate for
  # <service>.<tailnet>.ts.net (issued and renewed by Tailscale) and proxies plain HTTP to the UI.
  serviceHost = "${lib.removePrefix "svc:" cfg.tailscale.service}.${cfg.tailscale.tailnetDomain}";
  serveConfig = pkgs.writeTextDir "serve.json" (builtins.toJSON {
    Services.${cfg.tailscale.service} = {
      TCP."443".HTTPS = true;
      Web."${serviceHost}:443".Handlers."/".Proxy = "http://127.0.0.1:8080";
    };
  });
in
{
  options.services.cluster-dashboard = {
    agent = {
      enable = lib.mkEnableOption "the cluster dashboard metrics agent";
      listenTailnet = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Also serve the agent on tailscale0:${toString agentPort} for the collector.";
      };
    };

    enable = lib.mkEnableOption "the cluster dashboard and collector on this node";

    tailscale = {
      enable = lib.mkEnableOption "the Tailscale Service sidecar for the dashboard";
      service = lib.mkOption {
        type = lib.types.strMatching "svc:[a-z0-9-]+";
        default = "svc:dashboard";
        description = "Tailscale Service the sidecar hosts (HTTPS on TCP 443).";
      };
      tailnetDomain = lib.mkOption {
        type = lib.types.strMatching "[a-z0-9-]+\\.ts\\.net";
        default = "tailc8f497.ts.net";
        description = "MagicDNS suffix of the operator's Tailscale tailnet; the Service is https://<service>.<tailnetDomain>/.";
      };
      hostname = lib.mkOption {
        type = lib.types.str;
        default = "cluster-dashboard";
        description = "Device name of the sidecar in the Tailscale tailnet.";
      };
      tags = lib.mkOption {
        type = lib.types.listOf (lib.types.strMatching "tag:[a-z0-9-]+");
        default = [ "tag:svc" ];
        description = "Tags requested at login; Services can only be hosted by tagged devices.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      services.cluster-dashboard.agent.enable = true;
    })

    (lib.mkIf cfg.agent.enable {
      users.groups.cluster-dashboard.gid = gid;

      systemd.sockets.cluster-agent = {
        description = "Cluster dashboard metrics agent socket";
        wantedBy = [ "sockets.target" ];
        listenStreams = [ "${socketDir}/agent.sock" ]
          ++ lib.optional cfg.agent.listenTailnet (toString agentPort);
        socketConfig = {
          SocketMode = "0660";
          SocketGroup = "cluster-dashboard";
          DirectoryMode = "0755";
        };
      };

      systemd.services.cluster-agent = {
        description = "Cluster dashboard metrics agent";
        requires = [ "cluster-agent.socket" ];
        after = [ "cluster-agent.socket" ];
        # podman, tailscale, du, ss, systemctl and nixos-version, all read-only uses.
        path = [ podman pkgs.coreutils pkgs.iproute2 config.systemd.package config.services.tailscale.package "/run/current-system/sw" ];
        environment = {
          AGENT_PODMAN = "${podman}/bin/podman";
          AGENT_COLLECT = if cfg.enable then "1" else "0";
          AGENT_PEER_PORT = toString agentPort;
          PYTHONDONTWRITEBYTECODE = "1";
        };
        serviceConfig = {
          ExecStart = "${pkgs.python3}/bin/python3 -u ${./agent.py}";
          # Root is needed to list root Podman containers and read other users'
          # /proc/<pid>/net and state directories; the sandbox keeps it read-mostly.
          Restart = "on-failure";
          RestartSec = "10s";
          Nice = 10;
          IOSchedulingClass = "idle";
          MemoryMax = "192M";
          CPUQuota = "50%";
          ProtectSystem = "full";
          ProtectHome = "read-only";
          PrivateTmp = true;
          NoNewPrivileges = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectClock = true;
          ProtectHostname = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          SystemCallArchitectures = "native";
          RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];
        };
      };

      # Request and status-code counters per site on Caddy's admin endpoint (localhost:2019);
      # the agent maps each site to the unit listening on its reverse_proxy upstream.
      services.caddy.globalConfig = lib.mkIf config.services.caddy.enable ''
        metrics {
          per_host
        }
      '';

      # Not on public interfaces; the Headscale ACL limits sources to tag:ingress.
      networking.firewall.interfaces.tailscale0.allowedTCPPorts =
        lib.mkIf cfg.agent.listenTailnet [ agentPort ];
    })

    (lib.mkIf cfg.enable {
      virtualisation.oci-containers.containers.cluster-dashboard = {
        image = "docker.io/library/python:3.13-alpine@sha256:1e1f6334529d1fb26a2ef619d7cffb30a7c7d7cc1cc7338ebee283a58d1aeaca";
        cmd = [ "python" "-u" "/app/server.py" ];
        # Loopback only, for `ssh -L ${toString uiPort}:127.0.0.1:${toString uiPort}`; the
        # tailscale sidecar reaches 8080 inside the shared network namespace.
        ports = [ "127.0.0.1:${toString uiPort}:8080" ];
        volumes = [
          "${./app}:/app:ro"
          "${socketDir}:${socketDir}:ro"
        ];
        environment = {
          PYTHONDONTWRITEBYTECODE = "1";
          DASHBOARD_AGENT_SOCKET = "${socketDir}/agent.sock";
        };
        extraOptions = [
          "--read-only"
          "--user=65534:${toString gid}"
          "--cap-drop=ALL"
          "--security-opt=no-new-privileges"
          "--pids-limit=64"
          "--memory=128m"
          "--cpus=0.25"
          "--log-driver=journald"
        ];
      };

      systemd.services.podman-cluster-dashboard = {
        requires = [ "cluster-agent.socket" ];
        after = [ "cluster-agent.socket" ];
      };
    })

    (lib.mkIf (cfg.enable && cfg.tailscale.enable) {
      # TS_AUTHKEY for the first login only (TS_AUTH_ONCE); the node state then lives in
      # /var/lib/cluster-dashboard/tailscale. Interactive login is not an option:
      # containerboot kills `tailscale up` after 60 s and the container restarts.
      sops.secrets.cluster-dashboard_ts_env = {
        sopsFile = ./secrets.yaml;
        format = "yaml";
        mode = "0400";
        restartUnits = [ "podman-cluster-dashboard-ts.service" ];
      };

      virtualisation.oci-containers.containers.cluster-dashboard-ts = {
        image = "docker.io/tailscale/tailscale:v1.98.10@sha256:cdf5612ded5be1344f1a704b8c5e53496db97376bb533e5e15f141e48bf60cc0";
        dependsOn = [ "cluster-dashboard" ];
        environment = {
          TS_HOSTNAME = cfg.tailscale.hostname;
          TS_USERSPACE = "true";
          TS_STATE_DIR = "/var/lib/tailscale";
          TS_AUTH_ONCE = "true";
          TS_ACCEPT_DNS = "false";
          TS_SERVE_CONFIG = "/config/serve.json";
          TS_EXTRA_ARGS = "--advertise-tags=${lib.concatStringsSep "," cfg.tailscale.tags}";
        };
        environmentFiles = [ config.sops.secrets.cluster-dashboard_ts_env.path ];
        volumes = [
          "/var/lib/cluster-dashboard/tailscale:/var/lib/tailscale"
          "${serveConfig}:/config:ro"
        ];
        extraOptions = [
          # The dashboard's own namespace: separate from the host and from Headscale's
          # tailscale0. Userspace networking needs no TUN device or capabilities.
          "--network=container:cluster-dashboard"
          "--read-only"
          "--tmpfs=/tmp:size=16m"
          "--cap-drop=ALL"
          "--security-opt=no-new-privileges"
          "--pids-limit=128"
          "--memory=192m"
          "--cpus=0.5"
          "--log-driver=journald"
        ];
      };

      # The sidecar lives in the dashboard's namespace and must follow its restarts.
      systemd.services.podman-cluster-dashboard-ts.partOf = [ "podman-cluster-dashboard.service" ];

      systemd.tmpfiles.rules = [
        "d /var/lib/cluster-dashboard 0700 root root -"
        "d /var/lib/cluster-dashboard/tailscale 0700 root root -"
      ];
    })
  ];
}
