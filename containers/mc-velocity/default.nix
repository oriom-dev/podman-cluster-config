{ config, pkgs, lib, ... }:

let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
  appName = "mc-velocity";
in
{
  # シークレットの設定
  sops.secrets."${appName}_env" = { sopsFile = ./secrets.yaml; format = "yaml"; };

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
        "@SECRETS_PATH@" = config.sops.secrets."${appName}_env".path;
      };
    } // 
    {
      ".config/velocity/velocity.toml".source = ./velocity.toml;
      ".local/share/mc-velocity/tailscale/.keep".text = "";
      ".local/share/mc-velocity/data/.keep".text = "";
    };
}
