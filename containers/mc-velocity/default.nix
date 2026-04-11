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
      # 静的ファイルとして純粋にコピーするだけ
      ".config/velocity/velocity.toml".source = ./velocity.toml;
    };
}
