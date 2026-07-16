#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  stop.sh — shuts everything down in the order that actually releases the AIPU.
#
#  Order matters. Killing the inference server before its sessions have stopped
#  leaves the AIPU device handle held, and the next run fails with
#  "Device or resource busy". So: stop sessions → stop server → stop containers.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

cd "$(dirname "$0")"

step() { printf '\n==> %s\n' "$*"; }
log()  { printf '  %s\n' "$*"; }

CONTAINER="Voyager-SDK"
if [ -f .env ]; then
    # shellcheck disable=SC1091
    set -a; . ./.env; set +a
    CONTAINER="${VOYAGER_CONTAINER:-Voyager-SDK}"
fi

# ── 1. Stop inference sessions (gracefully) ──────────────────────────────────
step "Stopping inference sessions"
if docker inspect "$CONTAINER" >/dev/null 2>&1; then
    SESSIONS="$(docker exec "$CONTAINER" \
        curl -s http://localhost:8001/inference/status 2>/dev/null || echo '')"

    if echo "$SESSIONS" | grep -q '"run_id"'; then
        # Ask the server to tear each session down properly. This is what lets
        # the worker run its cleanup and hand the AIPU back.
        echo "$SESSIONS" \
          | grep -o '"run_id":"[^"]*"' \
          | cut -d'"' -f4 \
          | while read -r rid; do
                log "stopping $rid"
                docker exec "$CONTAINER" curl -s -X POST \
                    http://localhost:8001/inference/stop \
                    -H 'Content-Type: application/json' \
                    -d "{\"run_id\":\"$rid\"}" >/dev/null 2>&1 || true
            done
        sleep 3
    else
        log "none running"
    fi
else
    log "$CONTAINER not present — skipping"
fi

# ── 2. Stop the inference server ─────────────────────────────────────────────
step "Stopping the inference server"
if docker inspect "$CONTAINER" >/dev/null 2>&1; then
    docker exec "$CONTAINER" pkill -f ai_server.py 2>/dev/null \
        && log "stopped" || log "was not running"
fi

# ── 3. Stop the dashboard ────────────────────────────────────────────────────
step "Stopping the dashboard"
docker compose down 2>/dev/null && log "containers down" || log "already down"

# ── 4. Stop MediaMTX ─────────────────────────────────────────────────────────
step "Stopping MediaMTX"
pkill -f mediamtx 2>/dev/null && log "stopped" || log "was not running"

printf '\n  All services stopped.\n\n'
