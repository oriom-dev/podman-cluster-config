{ config, pkgs, lib, ... }:
let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
  serverName = "example";
in
{
  podman.activeServices = [ 
    "mc-${serverName}-sidecar" 
    "mc-${serverName}" 
    "mc-backup-${serverName}" 
  ];

  sops.secrets."mc_${serverName}_env" = { sopsFile = ./secrets.yaml; format = "yaml"; };

  home.file = 
    # サイドカー
    helper.mkQuadlet {
      name = "mc-${serverName}-sidecar";
      templatePath = ../../templates/minecraft-world/tailscale.container.in;
      vars = { "@SERVER_NAME@" = serverName; };
    } // 
    # サーバー本体
    helper.mkQuadlet {
      name = "mc-${serverName}";
      templatePath = ../../templates/minecraft-world/world.container.in;
      vars = {
        "@SERVER_NAME@" = serverName;
        "@SECRETS_PATH@" = config.sops.secrets."mc_${serverName}_env".path;
      };
    } // 
    # バックアップコンテナ
    helper.mkQuadlet {
      name = "mc-backup-${serverName}";
      templatePath = ../../templates/minecraft-world/backup.container.in;
      vars = {
        "@SERVER_NAME@" = serverName;
        "@SECRETS_PATH@" = config.sops.secrets."mc_${serverName}_env".path;
      };
    };
}
