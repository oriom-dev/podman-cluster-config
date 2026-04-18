{ config, pkgs, lib, ... }:

let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
  appName = "mc-velocity";
in
{
  sops.secrets."mc-velocity_forwarding-secret" = { sopsFile = ./secrets.yaml; format = "yaml"; };

  podman.activeServices = [ "${appName}-tailscale" appName ];

  home.file = 
    helper.mkQuadlet {
      name = "${appName}-tailscale";
      templatePath = ./tailscale.container;
      vars = {
        "@TS_SECRET_PATH@" = config.podman.tailscaleAuthKeyPath;
        "@TS_LOGIN_SERVER@" = config.podman.tailscaleLoginServer;
      };
    } // 
    helper.mkQuadlet {
      name = appName;
      templatePath = ./mc-velocity.container;
      vars = {
        "@APP_NAME@" = appName;
        "@FORWARDING_SECRET_PATH@" = config.sops.secrets."mc-velocity_forwarding-secret".path;
      };
    } // 
    {
      ".config/velocity/velocity.toml".source = ./velocity.toml;
    };
}
