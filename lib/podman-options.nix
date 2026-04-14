{ lib, ... }:
{
  options.podman.activeServices = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "自動起動するPodmanサービスのリスト";
  };

  options.podman.tailscaleAuthKeyPath = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "各ホスト(ノード)固有のTailscale認証キーファイルのパス";
  };

  options.podman.tailscaleLoginServer = lib.mkOption {
    type = lib.types.str;
    default = "https://headscale.oriom.dev";
    description = "TailscaleのログインサーバーURL";
  };
}
