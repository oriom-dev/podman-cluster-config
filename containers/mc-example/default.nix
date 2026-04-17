{ config, pkgs, lib, ... }:
let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
  serverName = "example";
in
{
  podman.activeServices = [ 
    "mc-${serverName}-tailscale" 
    "mc-${serverName}" 
    "mc-${serverName}-backup" 
  ];

  sops.secrets."mc_${serverName}_env" = { sopsFile = ./secrets.yaml; format = "yaml"; };

  home.file = 
    # サイドカー
    helper.mkQuadlet {
      name = "mc-${serverName}-tailscale";
      templatePath = ../../templates/mc-world/tailscale.container.in;
      vars = {
        "@SERVER_NAME@" = serverName;
        "@TS_SECRET_PATH@" = config.podman.tailscaleAuthKeyPath;
        "@TS_LOGIN_SERVER@" = config.podman.tailscaleLoginServer;
      };
    } // 
    # サーバー本体
    helper.mkQuadlet {
      name = "mc-${serverName}";
      templatePath = ../../templates/mc-world/world.container.in;
      vars = {
        "@SERVER_NAME@" = serverName;
        "@SECRETS_PATH@" = config.sops.secrets."mc_${serverName}_env".path;
      };
    } // 
    # バックアップコンテナ
    helper.mkQuadlet {
      name = "mc-${serverName}-backup";
      templatePath = ../../templates/mc-world/backup.container.in;
      vars = {
        "@SERVER_NAME@" = serverName;
        "@SECRETS_PATH@" = config.sops.secrets."mc_${serverName}_env".path;
      };
    };
}
