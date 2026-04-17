{ config, pkgs, lib, ... }:

let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
  appName = "mc-velocity";
in
{
  sops.secrets."mc-velocity_forwarding-secret" = { sopsFile = ./secrets.yaml; format = "yaml"; };

  # 自動起動リストへの申告
  podman.activeServices = [ "${appName}-tailscale" appName ];

  home.file = 
    # サイドカー
    helper.mkQuadlet {
      name = "${appName}-tailscale";
      templatePath = ./tailscale.container;
      vars = {
        "@TS_SECRET_PATH@" = config.podman.tailscaleAuthKeyPath;
        "@TS_LOGIN_SERVER@" = config.podman.tailscaleLoginServer;
      };
    } // 
    # 本体
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
