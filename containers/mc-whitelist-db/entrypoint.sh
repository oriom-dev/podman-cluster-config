#!/bin/sh
set -eu

: "${DB_APP_PASSWORD:?DB_APP_PASSWORD is required}"

CERTS_DIR="${CERTS_DIR:-/cockroach/certs}"
DATA_DIR="${DATA_DIR:-/cockroach/cockroach-data}"
DB_HOSTNAME="${DB_HOSTNAME:-mc-whitelist-db.ts.home.arpa}"
LISTEN_ADDR="${LISTEN_ADDR:-127.0.0.1:26257}"
SQL_ADDR="${SQL_ADDR:-0.0.0.0:26258}"
HTTP_ADDR="${HTTP_ADDR:-127.0.0.1:8080}"
SQL_PORT="${SQL_ADDR##*:}"
SQL_BOOTSTRAP_ADDR="${SQL_BOOTSTRAP_ADDR:-127.0.0.1:${SQL_PORT}}"
ADVERTISE_SQL_ADDR="${ADVERTISE_SQL_ADDR:-${DB_HOSTNAME}:${SQL_PORT}}"
BOOTSTRAP_MARKER="${DATA_DIR}/.app-user-ready"

mkdir -p "$CERTS_DIR" "$DATA_DIR"

ensure_certs() {
  if [ -f "$CERTS_DIR/ca.crt" ]; then
    return
  fi

  cockroach cert create-ca --certs-dir="$CERTS_DIR" --ca-key="$CERTS_DIR/ca.key"
  cockroach cert create-node \
    127.0.0.1 localhost mc-whitelist-db "$DB_HOSTNAME" \
    --certs-dir="$CERTS_DIR" --ca-key="$CERTS_DIR/ca.key"
  cockroach cert create-client root --certs-dir="$CERTS_DIR" --ca-key="$CERTS_DIR/ca.key"
  chmod 600 "$CERTS_DIR"/*.key
}

start_node() {
  cockroach start-single-node \
    --certs-dir="$CERTS_DIR" \
    --listen-addr="$LISTEN_ADDR" \
    --sql-addr="$SQL_ADDR" \
    --advertise-sql-addr="$ADVERTISE_SQL_ADDR" \
    --http-addr="$HTTP_ADDR" \
    --store="$DATA_DIR" \
    "$@"
}

wait_for_sql() {
  attempts=0
  until cockroach sql --certs-dir="$CERTS_DIR" --host="$SQL_BOOTSTRAP_ADDR" -e "SELECT 1" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 120 ]; then
      echo "Timed out waiting for Cockroach SQL listener at $SQL_BOOTSTRAP_ADDR" >&2
      echo "Cockroach startup settings: listen=$LISTEN_ADDR sql=$SQL_ADDR advertise_sql=$ADVERTISE_SQL_ADDR" >&2
      exit 1
    fi
    sleep 1
  done
}

bootstrap_app_user() {
  escaped_password="$(printf "%s" "$DB_APP_PASSWORD" | sed "s/'/''/g")"

  cockroach sql --certs-dir="$CERTS_DIR" --host="$SQL_BOOTSTRAP_ADDR" -e "
    CREATE USER IF NOT EXISTS whitelist_auth;
    ALTER USER whitelist_auth WITH PASSWORD '${escaped_password}';
    GRANT ALL ON DATABASE defaultdb TO whitelist_auth;
    GRANT ALL ON SCHEMA public TO whitelist_auth;
  "
}

ensure_certs

if [ ! -f "$BOOTSTRAP_MARKER" ]; then
  start_node --background
  wait_for_sql
  bootstrap_app_user
  cockroach quit --certs-dir="$CERTS_DIR" --host="$SQL_BOOTSTRAP_ADDR" || true
  touch "$BOOTSTRAP_MARKER"
fi

exec start_node
