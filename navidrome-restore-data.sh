#!/bin/bash

# Restore Navidrome's data directory from one of the archives the `backups`
# container has taken.
#
# That directory is everything Navidrome knows apart from the music itself:
# users and their passwords, playlists, play counts, ratings, starred items,
# the Subsonic API tokens every client holds, the search index and the artwork
# cache.
#
#     chmod +x navidrome-restore-data.sh
#     ./navidrome-restore-data.sh
#
# The music collection is NOT in the archive and is not touched by this script.
# It is mounted read-only and is the one thing a backup of this size cannot
# sensibly hold; back it up wherever it actually lives.
set -euo pipefail
cd "$(dirname "$0")"

COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-navidrome-traefik-letsencrypt-docker-compose.yml}"
PROJECT="${COMPOSE_PROJECT_NAME:-navidrome}"
BACKUP_PATH="${DATA_BACKUPS_PATH:-/srv/navidrome-data/backups}"
RESTORE_PATH="${DATA_PATH:-/data}"

dc() { docker compose -f "$COMPOSE_FILE" -p "$PROJECT" "$@"; }

APP_CONTAINER="$(dc ps -aq navidrome | head -n 1)"
BACKUPS_CONTAINER="$(dc ps -aq backups | head -n 1)"
[ -n "$APP_CONTAINER" ] || { echo "the navidrome container was not found — is the stack up?" >&2; exit 1; }
[ -n "$BACKUPS_CONTAINER" ] || { echo "the backups container was not found — is the stack up?" >&2; exit 1; }

echo "--> All available data backups:"
docker exec "$BACKUPS_CONTAINER" sh -c "ls -1 $BACKUP_PATH" || true

echo "--> Copy and paste the backup name from the list above and press [ENTER]
--> Example: navidrome-data-backup-YYYY-MM-DD_hh-mm.tar.gz"
echo -n "--> "
read -r SELECTED
[ -n "$SELECTED" ] || { echo "nothing selected, nothing restored" >&2; exit 1; }

if ! docker exec "$BACKUPS_CONTAINER" sh -c "tar -tzf '${BACKUP_PATH}/${SELECTED}' > /dev/null"; then
  echo "that file is not a readable tar archive — nothing has been stopped or deleted" >&2
  exit 1
fi
echo "--> $SELECTED was selected and reads as a valid archive"

echo "--> Stopping Navidrome..."
docker stop "$APP_CONTAINER" > /dev/null

echo "--> Restoring the data directory..."
# The archive stores paths relative to /, so it extracts there. The directory
# is emptied first: a restore that merges leaves rows in the old database that
# the archive never had.
docker exec "$BACKUPS_CONTAINER" sh -c "rm -rf '${RESTORE_PATH:?}'/* && tar -zxpf '${BACKUP_PATH}/${SELECTED}' -C /"
echo "--> Data recovery completed."

echo "--> Starting Navidrome..."
docker start "$APP_CONTAINER" > /dev/null
echo "--> Navidrome answers once it has opened the restored database."
echo "--> Play counts and playlists are back immediately. If tracks are missing,"
echo "--> the archive predates them: trigger a scan from Settings, or wait for"
echo "--> the schedule."
