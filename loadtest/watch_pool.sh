#!/usr/bin/env bash
# Poll the load-test pool/event-loop telemetry during a run.
# Usage: ./watch_pool.sh http://<staging-ip>:3001 "$LOADTEST_KEY" [interval_seconds]
set -euo pipefail
HOST="${1:?usage: watch_pool.sh http://<ip>:3001 <LOADTEST_KEY> [interval]}"
KEY="${2:?LOADTEST_KEY required}"
INTERVAL="${3:-2}"
echo "polling ${HOST}/api/debug/pool every ${INTERVAL}s (Ctrl-C to stop)"
while true; do
  printf '%s  ' "$(date +%H:%M:%S)"
  curl -s -H "x-loadtest-key: ${KEY}" "${HOST}/api/debug/pool" || echo "(request failed)"
  echo
  sleep "${INTERVAL}"
done
