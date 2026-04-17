{ config, pkgs, lib, ... }:

{
  # 引数としてワールドごとの設定を受け取る関数を定義
  mkWorld = { 
    serverName,
    sopsFile ? null,
    extraPatches ? [],
    extraEnv ? {}
  }: 
  let
    helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };
    
    envStrings = lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "Environment=${k}=${v}") extraEnv);

    basePatch = ./patch.yaml;
    allPatches = [ basePatch ] ++ extraPatches;
    
    patchMounts = map (p: "Volume=${builtins.toString p}:/etc/mc-patches/${builtins.baseNameOf p}:ro") allPatches;
    patchMountsStr = lib.concatStringsSep "\n" patchMounts;
    
    patchPaths = map (p: "/etc/mc-patches/${builtins.baseNameOf p}") allPatches;
    patchDefsStr = lib.concatStringsSep "," patchPaths;
  in {
    podman.activeServices = [
      "mc-${serverName}-tailscale"
      "mc-${serverName}"
      "mc-${serverName}-backup"
    ];

    sops.secrets."mc_common_env" = { 
      sopsFile = ./secrets.yaml; 
      format = "yaml"; 
    };

    sops.secrets."mc-${serverName}_env" = lib.mkIf (sopsFile != null) { 
      sopsFile = sopsFile; 
      format = "yaml"; 
    };

    home.file = 
      helper.mkQuadlet {
        name = "mc-${serverName}-tailscale";
        templatePath = ./tailscale.container.in;
        vars = {
          "@SERVER_NAME@" = serverName;
          "@TS_SECRET_PATH@" = config.podman.tailscaleAuthKeyPath;
          "@TS_LOGIN_SERVER@" = config.podman.tailscaleLoginServer;
        };
      } // 
      helper.mkQuadlet {
        name = "mc-${serverName}";
        templatePath = ./world.container.in;
        vars = {
          "@SERVER_NAME@" = serverName;
          "@COMMON_SECRETS_PATH@" = config.sops.secrets."mc_common_env".path;
          "@WORLD_SECRETS_PATH@" = if sopsFile != null then "EnvironmentFile=${config.sops.secrets."mc-${serverName}_env".path}" else "";
          "@PATCH_MOUNTS@" = patchMountsStr;
          "@PATCH_DEFINITIONS@" = patchDefsStr;
          "@EXTRA_ENV@" = envStrings;
        };
      } // 
      helper.mkQuadlet {
        name = "mc-${serverName}-backup";
        templatePath = ./backup.container.in;
        vars = {
          "@SERVER_NAME@" = serverName;
          "@COMMON_SECRETS_PATH@" = config.sops.secrets."mc_common_env".path;
          "@WORLD_SECRETS_PATH@" = if sopsFile != null then "EnvironmentFile=${config.sops.secrets."mc-${serverName}_env".path}" else "";
        };
      };
  };
}
