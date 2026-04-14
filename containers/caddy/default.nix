{ config, pkgs, lib, ... }:
let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
in
{
  podman.activeServices = [ "caddy-tailscale" "caddy" ];

  home.file = 
    # Caddy専用のIngressサイドカー
    helper.mkQuadlet {
      name = "caddy-tailscale";
      templatePath = ./tailscale.container;
      vars = {
        "@TS_SECRET_PATH@" = config.podman.tailscaleAuthKeyPath;
        "@TS_LOGIN_SERVER@" = config.podman.tailscaleLoginServer;
      };
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
