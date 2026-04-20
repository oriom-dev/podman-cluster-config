#!/bin/sh
set -eu

: "${DB_APP_PASSWORD:?DB_APP_PASSWORD is required}"

CERTS_DIR="/cockroach/certs"
DATA_DIR="/cockroach/cockroach-data"
NODE_SQL_ADDR="mc-whitelist-db.ts.home.arpa:26258"

mkdir -p "$CERTS_DIR" "$DATA_DIR"

if [ ! -f "$CERTS_DIR/ca.crt" ]; then
  cockroach cert create-ca --certs-dir="$CERTS_DIR" --ca-key="$CERTS_DIR/ca.key"
  cockroach cert create-node \
    127.0.0.1 localhost mc-whitelist-db mc-whitelist-db.ts.home.arpa \
    --certs-dir="$CERTS_DIR" --ca-key="$CERTS_DIR/ca.key"
  cockroach cert create-client root --certs-dir="$CERTS_DIR" --ca-key="$CERTS_DIR/ca.key"
  chmod 600 "$CERTS_DIR"/*.key
fi

if [ ! -f "$DATA_DIR/.app-user-ready" ]; then
  cockroach start-single-node \
    --certs-dir="$CERTS_DIR" \
    --listen-addr=127.0.0.1:26257 \
    --sql-addr=0.0.0.0:26258 \
    --advertise-sql-addr="$NODE_SQL_ADDR" \
    --http-addr=127.0.0.1:8080 \
    --store="$DATA_DIR" \
    --background

  until cockroach sql --certs-dir="$CERTS_DIR" --host=127.0.0.1:26257 -e "SELECT 1" >/dev/null 2>&1; do
    sleep 1
  done

  cockroach sql --certs-dir="$CERTS_DIR" --host=127.0.0.1:26257 -e "
    CREATE USER IF NOT EXISTS whitelist_auth;
    ALTER USER whitelist_auth WITH PASSWORD '${DB_APP_PASSWORD}';
    GRANT ALL ON DATABASE defaultdb TO whitelist_auth;
    GRANT ALL ON SCHEMA public TO whitelist_auth;
  "

  cockroach quit --certs-dir="$CERTS_DIR" --host=127.0.0.1:26257 || true
  touch "$DATA_DIR/.app-user-ready"
fi

exec cockroach start-single-node \
  --certs-dir="$CERTS_DIR" \
  --listen-addr=127.0.0.1:26257 \
  --sql-addr=0.0.0.0:26258 \
  --advertise-sql-addr="$NODE_SQL_ADDR" \
  --http-addr=127.0.0.1:8080 \
  --store="$DATA_DIR"
