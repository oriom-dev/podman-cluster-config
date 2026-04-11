{ config, pkgs, lib, ... }:
let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
in
{
  home.file = 
    # Caddy専用のIngressサイドカー
    helper.mkQuadlet {
      name = "caddy-tailscale";
      templatePath = ./tailscale.container;
    } // 
    # Caddy本体
    helper.mkQuadlet {
      name = "caddy";
      templatePath = ./caddy.container;
    } // 
    {
      # Caddyfileの配置
      ".config/caddy/Caddyfile".source = ./Caddyfile;
    };
}
