# Oriom Podman cluster configuration

## 開発環境

Dev Container 対応エディターでこのリポジトリを開き以下を実行してください

```sh
nix develop
```

## ビルドとデプロイ

```sh
nix flake show
nix build .#nixosConfigurations.kagoya-vps.config.system.build.toplevel
./bin/vps-build.sh
```

対象はサーバーと同じ `x86_64-linux` です。コンテナーは NixOS システムではなく、systemd やサービスの動作確認には別の NixOS 環境が必要です。Podman をコンテナー内で実行するには別途エンジンへの接続や設定が必要です。

SOPS の age 鍵は必要に応じて `.config/age.txt` に配置してください。このファイルは Git 管理対象外です。
