{ config, pkgs, ... }:
let
  serverName = "lobby";
  sidecarTpl = builtins.readFile ../../templates/minecraft-world/tailscale.container.in;
  serverTpl = builtins.readFile ../../templates/minecraft-world/world.container.in;
  homeDir = config.home.homeDirectory;
in {
  sops.secrets."mc_${serverName}_env" = { sopsFile = ./secrets.yaml; format = "yaml"; };
  
  home.file = {
    ".config/containers/systemd/mc-${serverName}-sidecar.container".text = 
      builtins.replaceStrings ["@SERVER_NAME@"] [serverName] sidecarTpl;
      
    ".config/containers/systemd/mc-${serverName}.container".text = 
      builtins.replaceStrings ["@SERVER_NAME@" "@HOME_DIR@" "@SECRETS_PATH@"] 
      [serverName homeDir config.sops.secrets."mc_${serverName}_env".path] serverTpl;
  };
}
