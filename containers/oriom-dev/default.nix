# oriom.dev portfolio (https://github.com/oriom-dev/oriom-dev). The repository's NixOS
# module runs the server in a container; this adapter owns the deployment choices.
#   HTTP/1.0–3  Caddy -> 127.0.0.1:3020
#   HTTP/0.9    caddy-l4 on :80 (see ../caddy) -> 127.0.0.1:3021
#   CoAP        UDP 5683, public
#   Gopher      TCP 70, public (7070 inside the container)
#   Gemini      TCP 1965, public, self-signed certificate made once (TOFU)
{ config, inputs, lib, ... }:
{
  imports = [ inputs.oriom-dev.nixosModules.default ];

  config = lib.mkIf config.services.oriom-dev.enable {
    services.oriom-dev = {
      domain = "oriom.dev";
      port = 3020;
      http09Port = 3021;
      coapPort = 5683;
      gopherPort = 70;
      geminiPort = 1965;
      caddyLayer4 = true;
      # Live cluster numbers: the server publishes an allowlisted summary only
      # (node names, CPU, memory, traffic, uptime, running container names).
      agentSocket = "/run/cluster-agent/agent.sock";
      agentGid = 29925;
      # ADMIN_PATH: the admin page's unguessable path (shown only over HTTPS)
      environmentFile = config.sops.secrets."oriom-dev_env".path;
    };
    sops.secrets."oriom-dev_env" = {
      sopsFile = ./secrets.yaml;
      format = "yaml";
      mode = "0400";
      restartUnits = [ "podman-oriom-dev.service" ];
    };
    # CoAP, Gopher and Gemini cannot go through Caddy.
    cluster.containerPolicy.publicPortContainers = [ "oriom-dev" ];
    systemd.services.podman-oriom-dev = {
      requires = [ "cluster-agent.socket" ];
      after = [ "cluster-agent.socket" ];
    };
  };
}
