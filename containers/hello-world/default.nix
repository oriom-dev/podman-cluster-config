{ config, pkgs, lib, ... }:
let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
  appName = "hello-world";
  ossCommitHash = "61136d8";
in
{
  podman.activeServices = [ "${appName}-tailscale" appName ];

  home.file = 
    # 共通サイドカーテンプレートの呼び出し
    helper.mkQuadlet {
      name = "${appName}-tailscale";
      templatePath = ../../templates/http/tailscale.container.in;
      vars = { "@APP_NAME@" = appName; };
    } // 
    # アプリ本体
    helper.mkQuadlet {
      name = appName;
      templatePath = ./hello-world.container.in;
      vars = {
        "@APP_NAME@" = appName;
        "@COMMIT_HASH@" = ossCommitHash;
      };
    } // 
    {
      # Containerfileの生成
      ".config/containers/build/${appName}/Containerfile".text = 
        builtins.replaceStrings [ "@COMMIT_HASH@" ] [ ossCommitHash ] (builtins.readFile ./Containerfile.in);
    };
}
