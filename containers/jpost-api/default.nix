{ config, pkgs, lib, ... }:
let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
  appName = "jpost-api";
in
{
  sops.secrets."${appName}_env" = { sopsFile = ./secrets.yaml; format = "yaml"; };
  podman.activeServices = [ "${appName}-tailscale" "${appName}-image" appName ];

  home.file = 
    helper.mkQuadlet {
      name = "${appName}-tailscale";
      templatePath = ../../templates/http/tailscale.container.in;
      vars = { "@APP_NAME@" = appName; };
    } // 
    helper.mkQuadlet {
      name = "${appName}-image";
      type = "image";
      templatePath = ./jpost-api.image;
    } // 
    helper.mkQuadlet {
      name = appName;
      templatePath = ./jpost-api.container;
      vars = {
        "@SECRETS_PATH@" = config.sops.secrets."${appName}_env".path;
      };
    } // 
    {
      ".config/containers/build/${appName}/Containerfile".source = ./Containerfile;
      ".config/containers/build/${appName}/src" = {
        source = ./src;
        recursive = true;
      };
    };
}
