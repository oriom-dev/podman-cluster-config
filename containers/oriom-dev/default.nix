# oriom.dev portfolio (https://github.com/oriom-dev/oriom-dev). The repository's NixOS
# module runs the server in a container; this adapter owns the deployment choices.
#   HTTP/1.0–3  Caddy -> 127.0.0.1:3020
#   HTTP/0.9    caddy-l4 on :80 (see ../caddy) -> 127.0.0.1:3021
#   CoAP        UDP 5683, public
{ config, inputs, lib, ... }:
{
  imports = [ inputs.oriom-dev.nixosModules.default ];

  config = lib.mkIf config.services.oriom-dev.enable {
    services.oriom-dev = {
      domain = "oriom.dev";
      port = 3020;
      http09Port = 3021;
      coapPort = 5683;
      caddyLayer4 = true;
      # Live cluster numbers: the server publishes an allowlisted summary only
      # (node names, CPU, memory, traffic, uptime, running container names).
      agentSocket = "/run/cluster-dashboard/agent.sock";
      agentGid = 29925;
    };
    # CoAP is UDP and cannot go through Caddy.
    cluster.containerPolicy.publicPortContainers = [ "oriom-dev" ];
    systemd.services.podman-oriom-dev = {
      requires = [ "cluster-dashboard-agent.socket" ];
      after = [ "cluster-dashboard-agent.socket" ];
    };
  };
}
