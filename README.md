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

`nix flake check` で全ホストの評価・ビルドとコンテナポリシー（loopback 限定・ポート重複禁止・digest 固定）を検査します。

## 構成

| パス | 役割 |
|---|---|
| `flake.nix` | ホスト (`nixosConfigurations.<host>`)、`#vps` CLI、devShell、checks |
| `hosts/<node>/` | ホスト固有値と、そのホストで有効にするサービス |
| `hosts/common/` | 全ノード共通の基盤設定 |
| `modules/` | プロジェクト共通の NixOS モジュール（コンテナポリシーなど） |
| `containers/<name>/` | サービスごとの宣言・ソース・秘密情報・Caddy ルート（`containers/README.md`） |
| `lib/` | Nix ヘルパーと `bin/vps-*.sh` のデプロイ処理 |
| `bin/` | ビルド・デプロイ・ロールバック・秘密情報編集 |
| `docs/cluster-roadmap.md` | 今後のクラスタ化ロードマップ |

## 秘密情報

SOPS のポリシーはリポジトリ直下の `.sops.yaml` 1つに集約しています。秘密情報は運用者と、そのサービスを動かすホストの鍵だけで暗号化します。ルールに一致しない新規ファイルは暗号化できません。

```sh
./bin/secret-edit.sh <service>
```

SOPS の age 鍵は必要に応じて `.config/age.txt`（パーミッション 600）に配置してください。`.config/` は Git 管理対象外です。
