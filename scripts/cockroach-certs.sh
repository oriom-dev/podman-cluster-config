#!/usr/bin/env -S NIXPKGS_ALLOW_UNFREE=1 nix-shell
#!nix-shell -i bash -p cockroachdb sops jq

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINERS_DIR="$PROJECT_ROOT/containers"

echo "CockroachDB 証明書発行・管理スクリプト"
echo "----------------------------------------"

get_existing_container() {
    local prompt_msg="$1"
    local container_name=""
    while true; do
        read -r -p "$prompt_msg" container_name
        if [ -z "$container_name" ]; then
            echo ""
            return
        fi
        if [ -d "$CONTAINERS_DIR/$container_name" ]; then
            echo "$container_name"
            return
        else
            echo "エラー: コンテナディレクトリ '$CONTAINERS_DIR/$container_name' が存在しません。もう一度入力してください。" >&2
        fi
    done
}

MAIN_CONTAINER=""
while true; do
    MAIN_CONTAINER=$(get_existing_container "メインコンテナ名を入力してください (例: db): ")
    if [ -n "$MAIN_CONTAINER" ]; then
        break
    else
        echo "メインコンテナ名は必須です。" >&2
    fi
done

MAIN_DIR="$CONTAINERS_DIR/$MAIN_CONTAINER"
CA_SECRET_FILE="$MAIN_DIR/local-secrets.yaml"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"; echo "一時ディレクトリを削除しました。"' EXIT

ensure_sops_file() {
    local target_file="$1"
    if [ ! -f "$target_file" ]; then
        echo "  -> $target_file を新規作成します。"
        echo "{}" | sops encrypt --input-type json --output-type yaml --filename-override "$target_file" > "$target_file"
    fi
}

echo ""
if [ -f "$CA_SECRET_FILE" ]; then
    echo "[CA] $CA_SECRET_FILE が存在します。既存のCAキーを利用します。"
    sops decrypt --extract '["ca_crt"]' "$CA_SECRET_FILE" > "$TMP_DIR/ca.crt"
    sops decrypt --extract '["ca_key"]' "$CA_SECRET_FILE" > "$TMP_DIR/ca.key"
    chmod 600 "$TMP_DIR/ca.key"
else
    echo "[CA] $CA_SECRET_FILE が存在しません。新規CAを作成します。"
    cockroach cert create-ca --certs-dir="$TMP_DIR" --ca-key="$TMP_DIR/ca.key"

    ensure_sops_file "$CA_SECRET_FILE"
    jq -Rs . "$TMP_DIR/ca.crt" | sops set --value-stdin "$CA_SECRET_FILE" '["ca_crt"]'
    jq -Rs . "$TMP_DIR/ca.key" | sops set --value-stdin "$CA_SECRET_FILE" '["ca_key"]'
    echo "  -> 生成し、暗号化しました。"
fi

echo "----------------------------------------"
echo "[サーバー証明書の発行]"
echo "複数のコンテナに対して連続して発行できます。終了する場合は空欄のままEnterを押してください。"

while true; do
    echo ""
    SERVER_CONTAINER=$(get_existing_container "サーバー証明書を配置するコンテナ名を入力 (空欄で終了): ")
    if [ -z "$SERVER_CONTAINER" ]; then
        break
    fi

    SERVER_DIR="$CONTAINERS_DIR/$SERVER_CONTAINER"
    SERVER_SECRET_FILE="$SERVER_DIR/secrets.yaml"

    read -r -p "ノード名/IP (複数ある場合はスペース区切り, 空欄の場合は '$SERVER_CONTAINER' を使用): " NODE_NAMES
    NODE_NAMES=${NODE_NAMES:-$SERVER_CONTAINER}

    echo "  -> サーバー証明書を生成します (対象ノード: $NODE_NAMES) ..."

    rm -f "$TMP_DIR/node.crt" "$TMP_DIR/node.key"
    # shellcheck disable=SC2086
    cockroach cert create-node $NODE_NAMES --certs-dir="$TMP_DIR" --ca-key="$TMP_DIR/ca.key"

    ensure_sops_file "$SERVER_SECRET_FILE"
    jq -Rs . "$TMP_DIR/node.crt" | sops set --value-stdin "$SERVER_SECRET_FILE" '["node_crt"]'
    jq -Rs . "$TMP_DIR/node.key" | sops set --value-stdin "$SERVER_SECRET_FILE" '["node_key"]'
    jq -Rs . "$TMP_DIR/ca.crt" | sops set --value-stdin "$SERVER_SECRET_FILE" '["ca_crt"]'
done

echo "----------------------------------------"
echo "[クライアント証明書の発行]"
echo "複数のコンテナ・ユーザーに対して連続して発行できます。終了する場合は空欄のままEnterを押してください。"

while true; do
    echo ""
    CLIENT_CONTAINER=$(get_existing_container "クライアント証明書を配置するコンテナ名を入力 (空欄で終了): ")
    if [ -z "$CLIENT_CONTAINER" ]; then
        break
    fi

    CLIENT_DIR="$CONTAINERS_DIR/$CLIENT_CONTAINER"
    CLIENT_SECRET_FILE="$CLIENT_DIR/secrets.yaml"

    read -r -p "クライアント証明書を発行するDBユーザー名 (例: kysely): " CLIENT_USER
    if [ -z "$CLIENT_USER" ]; then
        echo "  -> ユーザー名が入力されなかったためスキップします。"
        continue
    fi

    echo "  -> クライアント証明書を生成します (ユーザー: $CLIENT_USER) ..."

    rm -f "$TMP_DIR/client.$CLIENT_USER.crt" "$TMP_DIR/client.$CLIENT_USER.key"
    cockroach cert create-client "$CLIENT_USER" --certs-dir="$TMP_DIR" --ca-key="$TMP_DIR/ca.key"

    ensure_sops_file "$CLIENT_SECRET_FILE"
    jq -Rs . "$TMP_DIR/client.$CLIENT_USER.crt" | sops set --value-stdin "$CLIENT_SECRET_FILE" '["client_crt"]'
    jq -Rs . "$TMP_DIR/client.$CLIENT_USER.key" | sops set --value-stdin "$CLIENT_SECRET_FILE" '["client_key"]'
    jq -Rs . "$TMP_DIR/ca.crt" | sops set --value-stdin "$CLIENT_SECRET_FILE" '["ca_crt"]'
done

echo "----------------------------------------"
echo "すべての処理が完了しました。"
