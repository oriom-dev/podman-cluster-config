{ config, pkgs, ... }:

{
  home.file = {
    # サイドカーとCaddy本体のQuadletファイルを配置
    ".config/containers/systemd/caddy-tailscale.container".source = ./caddy-tailscale.container;
    ".config/containers/systemd/caddy.container".source = ./caddy.container;
    
    # Caddyfileを配置
    ".config/caddy/Caddyfile".source = ./Caddyfile;
  };
}
