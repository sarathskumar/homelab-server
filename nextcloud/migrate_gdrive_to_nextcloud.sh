#!/usr/bin/env bash
#
# migrate_gdrive_to_nextcloud.sh
#
# Migrates specific folders/files from Google Drive to a self-hosted Nextcloud
# instance using rclone. See README.md in this folder for full setup steps.
#
# Prerequisites (one-time, see README.md):
#   1. rclone installed
#   2. rclone remote "gdrive" configured (Google Drive)
#   3. rclone remote "nextcloud" configured (WebDAV to your Nextcloud instance)
#
# Usage:
#   ./migrate_gdrive_to_nextcloud.sh --dry-run     # preview only, no changes
#   ./migrate_gdrive_to_nextcloud.sh --run         # actually copy the data
#
set -eo pipefail

# ---- Config -----------------------------------------------------------
# List specific Google Drive folders and/or files to migrate.
# Each entry is copied into DEST_REMOTE, preserving its own name as a subfolder.
# Examples:
#   "gdrive:ExampleFolder1"                    -> whole top-level folder
#   "gdrive:ExampleFolder2/Subfolder"          -> whole subfolder
#   "gdrive:ExampleFolder3/example_file.pdf"   -> a single file
SOURCE_PATHS=(
  "gdrive:ExampleFolder1"
  "gdrive:ExampleFolder2/Subfolder"
)

DEST_REMOTE="nextcloud:GoogleDriveMigration" # Base folder created in Nextcloud
LOG_DIR="$HOME/rclone-migration-logs"
LOG_FILE="$LOG_DIR/migrate_$(date +%Y%m%d_%H%M%S).log"
TRANSFERS=8           # parallel file transfers
CHECKERS=16           # parallel checks (listing/comparing)
BANDWIDTH_LIMIT=""    # e.g. "10M" to cap at 10MB/s, leave empty for no limit
EXCLUDES=(
  "*.tmp"
  "~$*"
  ".DS_Store"
)
# ------------------------------------------------------------------------

mkdir -p "$LOG_DIR"

if ! command -v rclone &>/dev/null; then
  echo "ERROR: rclone is not installed. Install it first: https://rclone.org/install/"
  exit 1
fi

if ! rclone listremotes | grep -q "^gdrive:$"; then
  echo "ERROR: rclone remote 'gdrive:' not found. Run 'rclone config' to set it up."
  exit 1
fi

if ! rclone listremotes | grep -q "^${DEST_REMOTE%%:*}:$"; then
  echo "ERROR: rclone remote '${DEST_REMOTE%%:*}:' not found. Run 'rclone config' to set it up."
  exit 1
fi

# Build exclude flags
EXCLUDE_FLAGS=()
for pattern in "${EXCLUDES[@]}"; do
  EXCLUDE_FLAGS+=(--exclude "$pattern")
done

BW_FLAG=()
if [[ -n "$BANDWIDTH_LIMIT" ]]; then
  BW_FLAG=(--bwlimit "$BANDWIDTH_LIMIT")
fi

MODE="${1:---dry-run}"

case "$MODE" in
  --dry-run)
    echo "Running in DRY-RUN mode — no files will be changed."
    RUN_FLAGS=(--dry-run)
    ;;
  --run)
    echo "Running LIVE — files will actually be copied."
    RUN_FLAGS=()
    ;;
  *)
    echo "Usage: $0 [--dry-run|--run]"
    exit 1
    ;;
esac

echo "Destination base: $DEST_REMOTE"
echo "Log file:          $LOG_FILE"
echo "Folders/files to migrate:"
printf '  - %s\n' "${SOURCE_PATHS[@]}"
echo ""

for SRC in "${SOURCE_PATHS[@]}"; do
  # Strip the "remote:" prefix (e.g. "gdrive:") before computing the name,
  # so "gdrive:ExampleFolder1" becomes just "ExampleFolder1"
  PATH_ONLY="${SRC#*:}"
  NAME="$(basename "$PATH_ONLY")"
  DEST="${DEST_REMOTE}/${NAME}"

  echo "=== Copying: $SRC -> $DEST ==="
  rclone copy "$SRC" "$DEST" \
    --transfers "$TRANSFERS" \
    --checkers "$CHECKERS" \
    --progress \
    --log-file "$LOG_FILE" \
    --log-level INFO \
    --drive-acknowledge-abuse \
    "${EXCLUDE_FLAGS[@]}" \
    "${BW_FLAG[@]}" \
    "${RUN_FLAGS[@]}"
  echo ""
done

echo "Done. Full log at: $LOG_FILE"
