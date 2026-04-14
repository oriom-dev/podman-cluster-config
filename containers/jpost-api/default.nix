{ config, pkgs, lib, ... }:
let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
  appName = "jpost-api";
in
{
  sops.secrets."${appName}_env" = { sopsFile = ./secrets.yaml; format = "yaml"; };
  podman.activeServices = [ "${appName}-tailscale" "${appName}-build" appName ];

  home.file = 
    helper.mkQuadlet {
      name = "${appName}-tailscale";
      templatePath = ../../templates/http/tailscale.container.in;
      vars = {
        "@APP_NAME@" = appName;
        "@TS_SECRET_PATH@" = config.podman.tailscaleAuthKeyPath;
        "@TS_LOGIN_SERVER@" = config.podman.tailscaleLoginServer;
      };
    } // 
    helper.mkQuadlet {
      name = appName;
      type = "build";
      templatePath = ./jpost-api.build;
    } // 
    helper.mkQuadlet {
      name = appName;
      templatePath = ./jpost-api.container.in;
      vars = {
        "@SECRETS_PATH@" = config.sops.secrets."${appName}_env".path;
      };
    } // 
    {
      ".config/containers/build/${appName}/Containerfile".source = ./Containerfile;
    };

  home.activation."copy_${appName}_src" = lib.hm.dag.entryAfter ["linkGeneration"] ''
    BUILD_DIR="$HOME/.config/containers/build/${appName}/src"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cp -rL ${./src}/* "$BUILD_DIR"/
    chmod -R u+w "$BUILD_DIR"
  '';
}
