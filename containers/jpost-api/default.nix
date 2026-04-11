{ config, pkgs, ... }:

let
  appName = "jpost-api";
  
  sidecarTemplate = builtins.readFile ../../templates/http/tailscale.container.in;
  appTemplate = builtins.readFile ./jpost-api.container.in;
  
  secretsPath = config.sops.secrets."${appName}_env".path;
in
{
  sops.secrets."${appName}_env" = {
    sopsFile = ./secrets.yaml;
    format = "yaml";
  };

  home.file = {
    # tailscale sidecar
    ".config/containers/systemd/${appName}-tailscale.container".text = 
      builtins.replaceStrings [ "@APP_NAME@" ] [ appName ] sidecarTemplate;

    # app quadlet
    ".config/containers/systemd/${appName}.container".text = 
      builtins.replaceStrings 
        [ "@APP_NAME@" "@SECRETS_PATH@" ] 
        [ appName secretsPath ] 
        appTemplate;

    # container
    ".config/containers/build/${appName}/src" = {
      source = ./src;
      recursive = true;
    };
  };
}
