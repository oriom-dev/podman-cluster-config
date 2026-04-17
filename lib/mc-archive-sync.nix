{ config, pkgs, lib, ... }:

let
  # ★ アーカイブ先ノードのTailscale MagicDNS名に変更してください
  archiveNode = "archive-vps"; 
in
{
  # 毎日午前5時に同期タイマーを起動 (バックアップコンテナが午前4時に実行されるため)
  systemd.user.timers."mc-archive-sync" = {
    Unit.Description = "Sync Minecraft Backups to Archive Node";
    Timer.OnCalendar = "*-*-* 05:00:00";
    Install.WantedBy = [ "timers.target" ];
  };

  systemd.user.services."mc-archive-sync" = {
    Unit.Description = "Rsync backups to Archive Node via Tailscale";
    Service = {
      Type = "oneshot";
      # rsync を使用してTailscale網を通過させる
      ExecStart = "${pkgs.writeShellScript "sync-backups" ''
        set -e
        # _backups で終わる全Podmanボリュームを検索
        for vol in $(podman volume ls -q | grep _backups); do
          MOUNTPOINT=$(podman volume inspect $vol --format '{{.Mountpoint}}')
          
          # アーカイブノード側に保存用ディレクトリを確保
          ssh ubuntu@${archiveNode} "mkdir -p ~/mc-archives/$vol"
          
          # 差分同期: 既存の古いバックアップをアーカイブノード側に残しつつ、新しい分だけ転送する
          ${pkgs.rsync}/bin/rsync -avz --ignore-existing "$MOUNTPOINT/" "ubuntu@${archiveNode}:~/mc-archives/$vol/"
        done
      ''}";
    };
  };
}
