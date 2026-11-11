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
| `bin/` | ビルド・デプロイ・ロールバック・秘密情報編集・Mosimo の信頼資材の配置 |
| `docs/cluster-roadmap.md` | 今後のクラスタ化ロードマップ |

## 秘密情報

SOPS のポリシーはリポジトリ直下の `.sops.yaml` 1つに集約しています。秘密情報は運用者と、そのサービスを動かすホストの鍵だけで暗号化します。ルールに一致しない新規ファイルは暗号化できません。

```sh
./bin/secret-edit.sh <service>
```

SOPS の age 鍵は必要に応じて `.config/age.txt`（パーミッション 600）に配置してください。`.config/` は Git 管理対象外です。

## Mosimo の信頼資材

BSAF を Nostr へ取り込む importer は、ルート鍵から認証局を経て発行された鍵署名チェーンで認可されます（`dev.jisaku.mosimo.attest`）。鍵署名は 2 年有効で、定期的な更新は不要です。失効は失効通知を公開したときにだけ反映されます。

鍵の発行は [`sd_2607/appview/bsaf/identity-cli.mjs`](https://github.com/jphacks/sd_2607/blob/main/appview/bsaf/PUBLISHER.md) をオフラインで実行し、出力先を `.config/mosimo-trust/` にします。ルート鍵・認証局鍵・PLC 管理鍵はこのディレクトリから出しません。

```sh
MOSIMO_PRIVATE_DIR=$(pwd)/.config/mosimo-trust node ../sd_2607/appview/bsaf/identity-cli.mjs verify
./bin/mosimo-trust-install.sh kagoya_vps1
```

配置されるのは publisher 用の `credentials.json`・`roots.json` と、Caddy が `/.well-known/mosimo/attest/revocations` で配信する `revocations.cbor` の 3 つだけです。公開設定は `receiver-export` の出力を `containers/mosimo-pds/public-information.json` へ反映します。
