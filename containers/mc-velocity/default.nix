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

  home.file = {
    # サイドカー (静的ファイルとして配置)
    ".config/containers/systemd/${appName}-tailscale.container".source = ./tailscale.container;

    # 本体 (静的ファイルとして配置)
    ".config/containers/systemd/${appName}.container".source = ./mc-velocity.container;

    # 設定ファイル (パスワードを注入して配置)
    ".config/velocity/velocity.toml".text = 
      builtins.replaceStrings 
        [ "@FORWARDING_SECRET@" ] 
        [ config.sops.placeholder."${appName}_secrets" ] # sops-nixが復号後の値に置換します
        velocityTemplate;
  };
}
