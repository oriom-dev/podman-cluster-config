{ config, pkgs, ... }:

let
  # 稼働させるコンテナモジュールのリスト（ここを編集するだけで追加・削除・マイグレーションが完了）
  activeContainers = [
    "cluster-network"
    "headscale"
    "caddy"
    "hello-world"
    "jpost-api"
    "mc-velocity"
  ];
in
{
  # リスト内の名前から相対パスを生成し、各コンテナの default.nix をインポートする
  imports = map (name: ../../containers/${name}/default.nix) activeContainers;

  # --- これより下はホストシステム固有の最小設定 ---
  home.username = "ubuntu";
  home.homeDirectory = "/home/ubuntu";
  home.stateVersion = "23.11";

  home.packages = with pkgs; [ git podman passt sops age ];

  # SOPSのグローバル設定（鍵のパス等）
  sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

  home.sessionVariables.DOCKER_HOST = "unix:///run/user/$(id -u)/podman/podman.sock";
  xdg.configFile."containers/containers.conf".text = ''
    [network]
    default_rootless_network_cmd = "pasta"
  '';
}
