#!/bin/bash
# Redeploy the awdev container WITHOUT losing the SQL timing history.
#
# podman logs only holds the CURRENT container's output, so every `podman rm -f awdev` throws away
# every [sql] line collected since the last deploy. That is how a full afternoon of timings was lost.
# This captures them to an append-only TSV first, so the numbers accumulate across redeploys and can
# eventually be summarised (box-and-whisker per query object, which is the point -- single runs vary
# by ~10x, so one measurement tells you almost nothing).
#
# Usage:  bash scripts/redeploy-dev.sh
#         bash scripts/redeploy-dev.sh --capture-only     # harvest timings, leave the container up
#
# Output: logs/sql-timings.tsv   ->  <iso8601>\t<ms>\t<object>
set -euo pipefail

cd "$(dirname "$0")/.."
LOG_DIR=logs
LOG_FILE="$LOG_DIR/sql-timings.tsv"
mkdir -p "$LOG_DIR"
[ -f "$LOG_FILE" ] || printf 'timestamp\tms\tobject\n' > "$LOG_FILE"

# Harvest whatever the running container has, as TSV. `|| true` so a missing container is not fatal.
if podman container exists awdev 2>/dev/null; then
  BEFORE=$(wc -l < "$LOG_FILE")
  podman logs -t awdev 2>&1 \
    | grep '\[sql\]' \
    | sed -E 's/^([0-9T:.+-]+)[^ ]* \[sql\] ([0-9]+)ms +(.*)$/\1\t\2\t\3/' \
    >> "$LOG_FILE" || true
  # De-duplicate. `podman logs` replays the CURRENT container's WHOLE buffer every time, so running
  # this twice without a redeploy in between appends every row again -- which would quietly inflate
  # counts and skew any distribution built from the file. Rows are (timestamp, ms, object) and the
  # timestamp is sub-microsecond, so an exact duplicate line is always a re-read, never two real
  # queries. Header is preserved by sorting only the body.
  { head -1 "$LOG_FILE"; tail -n +2 "$LOG_FILE" | sort -u; } > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"

  AFTER=$(wc -l < "$LOG_FILE")
  echo "captured $((AFTER - BEFORE)) new timing rows -> $LOG_FILE (total $((AFTER - 1)))"
fi

if [ "${1:-}" = "--capture-only" ]; then
  exit 0
fi

podman rm -f awdev >/dev/null 2>&1 || true
MSYS_NO_PATHCONV=1 podman run -d --name awdev \
  --env-file webapp/.env.dev \
  -e SQL_TIMING=1 \
  -p 127.0.0.1:3001:3000 \
  --restart unless-stopped \
  assessment-webapp:0.5.0-dev >/dev/null

sleep 5
podman ps --filter name=awdev --format '{{.Names}} {{.Status}} {{.Ports}}'
