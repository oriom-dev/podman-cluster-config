{ config, pkgs, lib, ... }:

let
  # 稼働させるコンテナモジュールのリスト
  activeModules = [
    "cluster-network"
    "headscale"
    "caddy"
    "hello-world"
    "jpost-api"
    "mc-whitelist-db"
    "mc-whitelist-auth"
    "mc-velocity"
    "mc-lobby"
    "mc-tompedia-lobby"
  ];
in
{
  imports = [
    ../../lib/podman-options.nix
    ../../lib/podman-host.nix
    ../../lib/mc-admin.nix
  ] ++ map (name: ../../containers/${name}/default.nix) activeModules;

  sops.secrets."tailscale_env" = { sopsFile = ./secrets.yaml; format = "yaml"; };
  podman.tailscaleAuthKeyPath = config.sops.secrets."tailscale_env".path;

  # --- これより下はホストシステム固有の最小設定 ---
  home.username = "ubuntu";
  home.homeDirectory = "/home/ubuntu";
  home.stateVersion = "23.11";

  # SOPSのグローバル設定
  sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
}
