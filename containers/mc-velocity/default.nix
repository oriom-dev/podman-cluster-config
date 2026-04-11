{ config, pkgs, lib, ... }:
let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
  appName = "mc-velocity";
in
{
  sops.secrets."${appName}_secrets" = { sopsFile = ./secrets.yaml; format = "yaml"; };

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
    } // 
    {
      # パスワードを注入する特有の設定
      ".config/velocity/velocity.toml".text = builtins.replaceStrings 
        [ "@FORWARDING_SECRET@" ] 
        [ config.sops.placeholder."${appName}_secrets" ] 
        (builtins.readFile ./velocity.toml.in);
    };
}
