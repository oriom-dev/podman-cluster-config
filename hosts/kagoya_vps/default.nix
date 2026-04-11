{ config, pkgs, lib, ... }:

let
  helper = import ../../lib/quadlet-helper.nix { inherit config pkgs lib; };

  # 稼働させるコンテナモジュールのリスト（ディレクトリ名のみを列挙）
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
  ] ++ map (name: ../../containers/${name}/default.nix) activeModules;

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

  home.file = helper.quadletGenerator;

  home.activation.startPodmanServices = lib.hm.dag.entryAfter ["writeBoundary"] ''
    PATH="${pkgs.systemd}/bin:$PATH"
    
    echo "Reloading systemd daemon..."
    $DRY_RUN_CMD systemctl --user daemon-reload
    
    echo "Starting container services..."
    ${if builtins.length config.podman.activeServices > 0 then ''
      $DRY_RUN_CMD systemctl --user start ${builtins.concatStringsSep ".service " config.podman.activeServices}.service || true
    '' else ''
      echo "No services to start."
    ''}
  '';
}
