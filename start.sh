#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  start.sh — the only command you need. Run it every time.
#
#    1. setup.sh          detect the board, write .env, prepare directories
#    2. docker compose pull   fetch the dashboard images
#    3. start_voyager.sh  MediaMTX + Voyager-SDK + inference server
#    4. docker compose up dashboard frontend + backend
#    5. health check
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

cd "$(dirname "$0")"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
log()  { printf '  %s\n' "$*"; }

step "[1/5] Environment"
./setup.sh

# shellcheck disable=SC1091
set -a; . ./.env; set +a

step "[2/5] Fetching dashboard images"
if docker compose pull 2>&1 | grep -qiE 'error|denied|not found'; then
    echo
    echo "  Could not pull the dashboard images."
    echo "  If the registry is private, log in first:"
    echo "      docker login"
    echo "  Then re-run ./start.sh"
    echo
    exit 1
fi
log "images ready"

step "[3/5] Inference stack"
./start_voyager.sh

step "[4/5] Dashboard"
docker compose up -d
log "containers started"

step "[5/5] Waiting for the backend"
for i in $(seq 1 30); do
    if curl -sf http://localhost/api/health >/dev/null 2>&1; then
        log "backend healthy"
        break
    fi
    [ "$i" -eq 30 ] && {
        echo
        echo "  Backend did not become healthy in 60s."
        echo "  Logs:  docker compose logs backend"
        echo
        exit 1
    }
    sleep 2
done

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

cat <<EOF

╔══════════════════════════════════════════════════════════╗
║  WGtech AI Dashboard is running                           ║
╠══════════════════════════════════════════════════════════╣
║  Dashboard:    http://localhost                           ║
║  From another machine on the LAN:                         ║
║                http://${IP:-<board-ip>}
╚══════════════════════════════════════════════════════════╝

  Next: read USER_GUIDE.md, then open the dashboard.
  Stop everything with ./stop.sh

EOF
