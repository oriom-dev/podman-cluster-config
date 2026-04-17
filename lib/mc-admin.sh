#!/usr/bin/env bash
set -e

COMMAND=$1
SERVER=$2
ARG3=$3
ARG4=$4

if [ -z "$COMMAND" ] || [ -z "$SERVER" ]; then
  echo "=========================================================="
  echo " Minecraft Admin CLI (mc-admin)"
  echo "=========================================================="
  echo "Usage: mc-admin <command> <server_name> [args]"
  echo "Commands:"
  echo "  init            : Initialize and generate a new world"
  echo "  upload <dir>    : Upload local world directory"
  echo "  download <dir>  : Download current world to local directory"
  echo "  migrate <node>  : Migrate world to another Tailscale node"
  echo "  backup-now      : Manually trigger a backup immediately"
  echo "  list-backups    : List short-term & long-term backups"
  echo "  restore <file> [local|archive] : Restore from a backup"
  echo "  test-backup <file> [local|archive] : Dry-run a backup on a random port"
  echo "  stop-test       : Stop and clean up the test server"
  echo "=========================================================="
  exit 1
fi

VOL_DATA="mc-${SERVER}_data"
VOL_BACKUPS="mc-${SERVER}_backups"
CONTAINER_BACKUP="systemd-mc-${SERVER}-backup"

if ! podman volume exists "$VOL_DATA" >/dev/null 2>&1; then
  podman volume create "$VOL_DATA" >/dev/null
fi
MOUNTPOINT=$(podman volume inspect "$VOL_DATA" --format '{{.Mountpoint}}')

# 以下の case 文は前回の内容と完全に同一です
case "$COMMAND" in
  init)
    echo "[*] Initializing new world for $SERVER..."
    systemctl --user stop mc-$SERVER.service || true
    rm -rf "$MOUNTPOINT/world"
    systemctl --user start mc-$SERVER.service
    echo "[+] Done. New world is generating."
    ;;
  upload)
    echo "[*] Uploading $ARG3 to $SERVER..."
    systemctl --user stop mc-$SERVER.service || true
    mkdir -p "$MOUNTPOINT/world"
    rsync -avz --delete "$ARG3/" "$MOUNTPOINT/world/"
    systemctl --user start mc-$SERVER.service
    echo "[+] Upload complete."
    ;;
  download)
    echo "[*] Downloading world from $SERVER to $ARG3..."
    mkdir -p "$ARG3"
    rsync -avz "$MOUNTPOINT/world/" "$ARG3/"
    echo "[+] Download complete."
    ;;
  migrate)
    echo "[*] Migrating $SERVER to $ARG3..."
    systemctl --user stop mc-$SERVER.service || true
    ssh ubuntu@$ARG3 "podman volume create $VOL_DATA >/dev/null 2>&1 || true"
    TARGET_MOUNT=$(ssh ubuntu@$ARG3 "podman volume inspect $VOL_DATA --format '{{.Mountpoint}}'")
    rsync -avz --delete "$MOUNTPOINT/" "ubuntu@$ARG3:$TARGET_MOUNT/"
    echo "[+] Migration complete."
    ;;
  backup-now)
    echo "[*] Triggering manual backup for $SERVER..."
    podman exec "$CONTAINER_BACKUP" /usr/local/bin/backup
    echo "[+] Backup completed successfully."
    ;;
  list-backups)
    echo "=== Short-term Backups (Local) ==="
    podman run --rm -v "$VOL_BACKUPS:/backups:ro" alpine ls -lh /backups | grep "\.tgz" || echo "  (No backups found)"
    echo -e "\n=== Long-term Backups (Archive: $ARCHIVE_NODE) ==="
    if [ -n "$ARCHIVE_NODE" ] && ping -c 1 -W 1 "$ARCHIVE_NODE" >/dev/null 2>&1; then
       ssh ubuntu@$ARCHIVE_NODE "ls -lh ~/mc-archives/$VOL_BACKUPS/ 2>/dev/null" | grep "\.tgz" || echo "  (No backups)"
    else
       echo "  (Archive node unconfigured or unreachable)"
    fi
    ;;
  restore)
    SOURCE=${ARG4:-local}
    echo "[*] Restoring $ARG3 from $SOURCE..."
    systemctl --user stop mc-$SERVER.service || true
    if [ "$SOURCE" = "local" ]; then
       podman run --rm -v "$VOL_BACKUPS:/backups:ro" -v "$VOL_DATA:/data:Z" alpine sh -c "rm -rf /data/* && tar -xzf /backups/$ARG3 -C /data"
    elif [ "$SOURCE" = "archive" ]; then
       ssh ubuntu@$ARCHIVE_NODE "cat ~/mc-archives/$VOL_BACKUPS/$ARG3" | podman run -i --rm -v "$VOL_DATA:/data:Z" alpine sh -c "rm -rf /data/* && tar -xzf - -C /data"
    fi
    systemctl --user start mc-$SERVER.service
    echo "[+] Restore complete."
    ;;
  test-backup)
    SOURCE=${ARG4:-local}
    TEMP_VOL="mc-${SERVER}_test_data"
    TEST_CONTAINER="mc-${SERVER}-test"
    echo "[*] Setting up isolated environment..."
    podman rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true
    podman volume rm -f "$TEMP_VOL" >/dev/null 2>&1 || true
    podman volume create "$TEMP_VOL" >/dev/null
    if [ "$SOURCE" = "local" ]; then
       podman run --rm -v "$VOL_BACKUPS:/backups:ro" -v "$TEMP_VOL:/data:Z" alpine sh -c "tar -xzf /backups/$ARG3 -C /data"
    elif [ "$SOURCE" = "archive" ]; then
       ssh ubuntu@$ARCHIVE_NODE "cat ~/mc-archives/$VOL_BACKUPS/$ARG3" | podman run -i --rm -v "$TEMP_VOL:/data:Z" alpine sh -c "tar -xzf - -C /data"
    fi
    podman run -d --rm --name "$TEST_CONTAINER" -P -v "$TEMP_VOL:/data:Z" -e EULA=TRUE -e TYPE=PAPER -e ONLINE_MODE=false docker.io/itzg/minecraft-server:latest >/dev/null
    TEST_PORT=$(podman port "$TEST_CONTAINER" 25565/tcp | awk -F: '{print $2}')
    HOST_IP=$(tailscale ip -4)
    echo "[+] Connect your Minecraft client to: $HOST_IP:$TEST_PORT"
    ;;
  stop-test)
    echo "[*] Clean up test server..."
    podman rm -f "mc-${SERVER}-test" >/dev/null 2>&1 || true
    podman volume rm -f "mc-${SERVER}_test_data" >/dev/null 2>&1 || true
    echo "[+] Done."
    ;;
  *)
    echo "Unknown command: $COMMAND"
    exit 1
    ;;
esac
