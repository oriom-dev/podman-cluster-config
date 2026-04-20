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
BOOTSTRAP_LOG="${DATA_DIR}/bootstrap-start.log"

echo "[mc-whitelist-db] entrypoint version 2026-04-20.2" >&2

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
  bootstrap_pid="${1:?bootstrap pid is required}"
  attempts=0
  until cockroach sql --certs-dir="$CERTS_DIR" --host="$SQL_BOOTSTRAP_ADDR" -e "SELECT 1" >/dev/null 2>&1; do
    if ! kill -0 "$bootstrap_pid" >/dev/null 2>&1; then
      echo "Cockroach bootstrap process exited before SQL became ready (pid=$bootstrap_pid)." >&2
      if [ -f "$BOOTSTRAP_LOG" ]; then
        echo "--- bootstrap log (last 200 lines) ---" >&2
        tail -n 200 "$BOOTSTRAP_LOG" >&2 || true
        echo "--- end bootstrap log ---" >&2
      fi
      exit 1
    fi

    attempts=$((attempts + 1))
    if [ "$attempts" -ge 120 ]; then
      echo "Timed out waiting for Cockroach SQL listener at $SQL_BOOTSTRAP_ADDR" >&2
      echo "Cockroach startup settings: listen=$LISTEN_ADDR sql=$SQL_ADDR advertise_sql=$ADVERTISE_SQL_ADDR" >&2
      if [ -f "$BOOTSTRAP_LOG" ]; then
        echo "--- bootstrap log (last 200 lines) ---" >&2
        tail -n 200 "$BOOTSTRAP_LOG" >&2 || true
        echo "--- end bootstrap log ---" >&2
      fi
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
  rm -f "$BOOTSTRAP_LOG"
  start_node >"$BOOTSTRAP_LOG" 2>&1 &
  bootstrap_pid=$!

  wait_for_sql "$bootstrap_pid"
  bootstrap_app_user

  if ! cockroach quit --certs-dir="$CERTS_DIR" --host="$SQL_BOOTSTRAP_ADDR" >/dev/null 2>&1; then
    # Cockroach v25 image may not provide the legacy `quit` command.
    kill "$bootstrap_pid" >/dev/null 2>&1 || true
  fi

  wait "$bootstrap_pid" || true
  touch "$BOOTSTRAP_MARKER"
fi

exec cockroach start-single-node \
  --certs-dir="$CERTS_DIR" \
  --listen-addr="$LISTEN_ADDR" \
  --sql-addr="$SQL_ADDR" \
  --advertise-sql-addr="$ADVERTISE_SQL_ADDR" \
  --http-addr="$HTTP_ADDR" \
  --store="$DATA_DIR"
