{ config, pkgs, lib, ... }:
let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
  appName = "hello-world";
  ossCommitHash = "61136d8";
in
{
  podman.activeServices = [ "${appName}-tailscale" "${appName}-build" appName ];

  home.file = 
    # サイドカー
    helper.mkQuadlet {
      name = "${appName}-tailscale";
      templatePath = ../../templates/http/tailscale.container.in;
      vars = { "@APP_NAME@" = appName; };
    } // 
    # イメージビルド定義
    helper.mkQuadlet {
      name = appName;
      type = "build";
      templatePath = ./hello-world.build.in;
      vars = {
        "@COMMIT_HASH@" = ossCommitHash;
      };
    } // 
    # コンテナ本体
    helper.mkQuadlet {
      name = appName;
      templatePath = ./hello-world.container.in;
      vars = {
        "@COMMIT_HASH@" = ossCommitHash;
      };
    } // 
    {
      ".config/containers/build/${appName}/Containerfile".source = ./Containerfile;
    };
}
