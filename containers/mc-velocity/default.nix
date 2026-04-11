{ config, pkgs, ... }:

let
  appName = "mc-velocity";
  
  # velocity.toml のテンプレートを読み込み
  velocityTemplate = builtins.readFile ./velocity.toml.in;
in
{
  # このコンテナ専用のシークレットを定義
  sops.secrets."${appName}_secrets" = {
    sopsFile = ./secrets.yaml;
    format = "yaml";
  };

  sops.templates."velocity.toml" = {
    path = "${config.home.homeDirectory}/.config/velocity/velocity.toml";
    content = builtins.replaceStrings 
      [ "@FORWARDING_SECRET@" ] 
      [ "<sops:${appName}_secrets>" ] 
      velocityTemplate;
  };

  home.file = {
    # サイドカー (静的ファイルとして配置)
    ".config/containers/systemd/${appName}-tailscale.container".source = ./tailscale.container;

    # 本体 (静的ファイルとして配置)
    ".config/containers/systemd/${appName}.container".source = ./mc-velocity.container;
  };
}
