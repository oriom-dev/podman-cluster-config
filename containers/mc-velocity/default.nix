{ config, pkgs, lib, ... }:

let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
  appName = "mc-velocity";
in
{
  sops.secrets."mc-velocity_forwarding-secret" = { sopsFile = ./secrets.yaml; format = "yaml"; };
  sops.secrets."mc-velocity_env" = { sopsFile = ./secrets.yaml; format = "yaml"; };

  podman.activeServices = [ "${appName}-tailscale" "${appName}-build" appName ];

  home.file = 
    helper.mkQuadlet {
      name = "${appName}-tailscale";
      templatePath = ./tailscale.container;
      vars = {
        "@TS_SECRET_PATH@" = config.podman.tailscaleAuthKeyPath;
        "@TS_LOGIN_SERVER@" = config.podman.tailscaleLoginServer;
      };
    } // 
    helper.mkQuadlet {
      name = appName;
      type = "build";
      templatePath = ./${appName}.build;
    } //
    helper.mkQuadlet {
      name = appName;
      templatePath = ./mc-velocity.container;
      vars = {
        "@APP_NAME@" = appName;
        "@FORWARDING_SECRET_PATH@" = config.sops.secrets."mc-velocity_forwarding-secret".path;
        "@SECRETS_PATH@" = config.sops.secrets."mc-velocity_env".path;
      };
    } // 
    {
      ".config/velocity/velocity.toml".source = ./velocity.toml;
      ".config/containers/build/${appName}/Containerfile".source = ./Containerfile;
    };

  home.activation."copy_${appName}_plugin_src" = lib.hm.dag.entryAfter ["linkGeneration"] ''
    BUILD_DIR="$HOME/.config/containers/build/${appName}/plugin-src"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cp -rL ${./plugin-src}/* "$BUILD_DIR"/
    chmod -R u+w "$BUILD_DIR"
  '';
}
