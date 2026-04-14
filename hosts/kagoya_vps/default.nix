{ config, pkgs, lib, ... }:

let
  # 稼働させるコンテナモジュールのリスト
  activeModules = [
    "cluster-network"
    "headscale"
    "caddy"
    "hello-world"
    "jpost-api"
    "mc-velocity"
  ];
in
{
  imports = [
    ../../lib/podman-options.nix
    ../../lib/podman-host.nix
  ] ++ map (name: ../../containers/${name}/default.nix) activeModules;

  sops.secrets."tailscale_env" = { sopsFile = ./secret.yaml; format = "yaml"; };
  podman.tailscaleAuthKeyPath = config.sops.secrets."tailscale_env".path;

  # --- これより下はホストシステム固有の最小設定 ---
  home.username = "ubuntu";
  home.homeDirectory = "/home/ubuntu";
  home.stateVersion = "23.11";

  # SOPSのグローバル設定
  sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
}
