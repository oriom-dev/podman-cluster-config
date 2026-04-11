{ config, pkgs, ... }:

let
  appName = "hello-world";
  ossCommitHash = "d9435b5a2e57ecf7b49bd613e54b67ce4d98a280";
  
  # 共通サイドカーテンプレートと、固有テンプレートの読み込み
  sidecarTemplate = builtins.readFile ../../templates/http/tailscale.container.in;
  appTemplate = builtins.readFile ./hello-world.container.in;
  containerfileTemplate = builtins.readFile ./Containerfile.in;
  
  secretsPath = config.sops.secrets."${appName}_env".path;
in
{
  home.file = {
    # tailscale sidecar
    ".config/containers/systemd/${appName}-tailscale.container".text = 
      builtins.replaceStrings [ "@APP_NAME@" ] [ appName ] sidecarTemplate;

    # app quadlet
    ".config/containers/systemd/${appName}.container".text = 
      builtins.replaceStrings 
        [ "@APP_NAME@" "@COMMIT_HASH@" ] 
        [ appName ossCommitHash ] 
        appTemplate;

    # container
    ".config/containers/build/${appName}/Containerfile".text = 
      builtins.replaceStrings [ "@COMMIT_HASH@" ] [ ossCommitHash ] containerfileTemplate;
  };
}
