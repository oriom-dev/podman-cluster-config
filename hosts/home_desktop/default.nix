{ config, pkgs, ... }:

let
  # worker-vpsで稼働させるコンテナのリスト
  activeContainers = [
    "cluster-network"
    "hello-world"
    "minecraft-server"
  ];
in
{
  # リストに基づいて各コンテナの設定（default.nix）をインポート
  imports = map (name: ../../containers/${name}/default.nix) activeContainers;

  # --- ホスト固有の最小設定 ---
  home.username = "ubuntu";
  home.homeDirectory = "/home/ubuntu";
  home.stateVersion = "23.11";

  home.packages = with pkgs; [ git podman passt sops age ];

  # SOPSの復号用キーパス
  sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

  # Rootless Podman環境変数
  home.sessionVariables.DOCKER_HOST = "unix:///run/user/$(id -u)/podman/podman.sock";
  xdg.configFile."containers/containers.conf".text = ''
    [network]
    default_rootless_network_cmd = "pasta"
  '';
}
