{ lib, ... }:
{
  options.podman = {
    activeServices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "自動起動するPodmanサービスのリスト";
    };

    tailscaleAuthKeyPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "各ホスト(ノード)固有のTailscale認証キーファイルのパス";
    };

    tailscaleLoginServer = lib.mkOption {
      type = lib.types.str;
      default = "https://headscale.oriom.dev";
      description = "TailscaleのログインサーバーURL";
    };

    minecraft = {
      servers = lib.mkOption {
        description = "Velocityでルーティングするマイクラサーバーのリスト";
        default = {};
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            domain = lib.mkOption {
              type = lib.types.str;
              description = "ワールドに紐づけるドメイン";
            };
            address = lib.mkOption {
              type = lib.types.str;
              description = "Podmanネットワーク内のバックエンドアドレス";
            };
          };
        });
      };
    };
  };
}
