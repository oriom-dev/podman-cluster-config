{ config, pkgs, lib, ... }:
let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
  appName = "hello-world";
  ossCommitHash = "d9435b5a2e57ecf7b49bd613e54b67ce4d98a280";
in
{
  sops.secrets."${appName}_env" = { sopsFile = ./secrets.yaml; format = "yaml"; };
  podman.activeServices = [ "${appName}-tailscale" "${appName}-image" appName ];

  home.file = 
    # サイドカー
    helper.mkQuadlet {
      name = "${appName}-tailscale";
      templatePath = ../../templates/http/tailscale.container.in;
      vars = { "@APP_NAME@" = appName; };
    } // 
    # イメージビルド定義
    helper.mkQuadlet {
      name = "${appName}-image";
      type = "image";
      templatePath = ./hello-world.image.in;
      vars = { "@COMMIT_HASH@" = ossCommitHash; };
    } // 
    # コンテナ本体
    helper.mkQuadlet {
      name = appName;
      templatePath = ./hello-world.container.in;
      vars = {
        "@SECRETS_PATH@" = config.sops.secrets."${appName}_env".path;
        "@COMMIT_HASH@" = ossCommitHash;
      };
    } // 
    {
      ".config/containers/build/${appName}/Containerfile".source = ./Containerfile;
    };
}
