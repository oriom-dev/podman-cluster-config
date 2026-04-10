{ config, pkgs, ... }:

let
  appName = "hello-world";
  ossCommitHash = "d9435b5a2e57ecf7b49bd613e54b67ce4d98a280";
  
  # 共通サイドカーテンプレートと、固有テンプレートの読み込み
  sidecarTemplate = builtins.readFile ../shared-templates/app-tailscale.container.in;
  appTemplate = builtins.readFile ./hello-world.container.in;
  containerfileTemplate = builtins.readFile ./Containerfile.in;
  
  homeDir = config.home.homeDirectory;
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
        [ "@APP_NAME@" "@HOME_DIR@" "@SECRETS_PATH@" "@COMMIT_HASH@" ] 
        [ appName homeDir secretsPath ossCommitHash ] 
        appTemplate;

    # container
    ".config/containers/build/${appName}/Containerfile".text = 
      builtins.replaceStrings [ "@COMMIT_HASH@" ] [ ossCommitHash ] containerfileTemplate;
  };
}
