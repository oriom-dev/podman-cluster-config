{ config, pkgs, lib, ... }:
let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
  appName = "hello-world";
  ossCommitHash = "d9435b5a2e57ecf7b49bd613e54b67ce4d98a280";
in
{
  podman.activeServices = [ "${appName}-tailscale" appName ];

  sops.secrets."${appName}_env" = { sopsFile = ./secrets.yaml; format = "yaml"; };

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
        "@HOME_DIR@" = config.home.homeDirectory;
        "@SECRETS_PATH@" = config.sops.secrets."${appName}_env".path;
        "@COMMIT_HASH@" = ossCommitHash;
      };
    } // 
    {
      # Containerfileの生成
      ".config/containers/build/${appName}/Containerfile".text = 
        builtins.replaceStrings [ "@COMMIT_HASH@" ] [ ossCommitHash ] (builtins.readFile ./Containerfile.in);
    };
}
