{ config, pkgs, lib, ... }:

let
  # ★ 長期バックアップ用のアーカイブノードのTailscale名 (ない場合は "" にする)
  archiveNode = "";
in
{
  home.packages = [
    (pkgs.writeShellScriptBin "mc-admin" ''
      export PATH="${lib.makeBinPath [ pkgs.rsync pkgs.tailscale pkgs.podman pkgs.openssh ]}:$PATH"
      export ARCHIVE_NODE="${archiveNode}"

      ${builtins.readFile ./mc-admin.sh}
    '')
  ];
}
