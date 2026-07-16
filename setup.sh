#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  setup.sh — one-time (and idempotent) environment preparation.
#
#  Detects everything that varies between boards instead of hardcoding it:
#    • the Voyager-SDK container's real name (case varies by SDK version)
#    • the SDK install path inside that container
#    • the host side of the SDK's shared mount (used to pass HLS to the backend)
#    • whether a USB camera is present
#  ...then writes a .env the rest of the stack can rely on.
#
#  Safe to re-run. start.sh calls it for you.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"

log()  { printf '  %s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

# ── 1. Prerequisites ─────────────────────────────────────────────────────────
step "Checking prerequisites"

command -v docker >/dev/null 2>&1 || die "docker not found. See HARDWARE_SETUP.md."
docker info >/dev/null 2>&1 || die "cannot talk to the docker daemon. Try: sudo usermod -aG docker \$USER (then re-login), or run with sudo."
log "docker ok"

if ! docker compose version >/dev/null 2>&1; then
    die "'docker compose' not available. Install the compose plugin."
fi
log "docker compose ok"

# ── 2. Find the Voyager-SDK container ────────────────────────────────────────
# Axelera's tooling has shipped this as both 'voyager-sdk' and 'Voyager-SDK'.
# Match case-insensitively rather than guessing.
step "Locating the Voyager-SDK container"

VOYAGER_CONTAINER="$(docker ps -a --format '{{.Names}}' \
    | grep -iE '^voyager-sdk$' | head -n 1 || true)"

if [ -z "$VOYAGER_CONTAINER" ]; then
    echo
    echo "  Could not find a Voyager-SDK container."
    echo "  Containers currently on this board:"
    docker ps -a --format '    - {{.Names}}  ({{.Image}})' || true
    echo
    die "Complete the Axelera SDK installation first — see HARDWARE_SETUP.md."
fi
log "container: $VOYAGER_CONTAINER"

# ── 3. Metis AIPU driver ─────────────────────────────────────────────────────
step "Checking the Metis AIPU driver"

DRIVER_VER="$(cat /sys/module/metis/version 2>/dev/null || true)"
if [ -z "$DRIVER_VER" ]; then
    if lsmod 2>/dev/null | grep -q '^metis'; then
        DRIVER_VER="loaded (version unknown)"
    else
        echo
        echo "  The 'metis' kernel module does not appear to be loaded."
        echo "  Try:  sudo modprobe metis"
        echo "  The dashboard will start, but inference will fail until this is fixed."
        echo
        DRIVER_VER="NOT LOADED"
    fi
fi
log "driver: $DRIVER_VER"

# ── 4. SDK path inside the container ─────────────────────────────────────────
step "Detecting the SDK path inside the container"

SDK_DIR=""
for candidate in /home/ubuntu/voyager-sdk /home/voyager-sdk /opt/voyager-sdk; do
    if docker exec "$VOYAGER_CONTAINER" test -d "$candidate" 2>/dev/null; then
        SDK_DIR="$candidate"
        break
    fi
done
[ -n "$SDK_DIR" ] || die "could not find the voyager-sdk directory inside $VOYAGER_CONTAINER."
log "SDK_DIR: $SDK_DIR"

# ── 5. Shared mount (how annotated HLS reaches the backend) ──────────────────
# The Voyager-SDK container is started by Axelera's own tooling and does NOT
# bind-mount the host's /tmp. So anything it writes to /tmp/hls is invisible to
# the backend container. It *does* have a shared mount, and we route through it.
step "Detecting the SDK's shared mount"

SHARED_HOST=""
SHARED_CONT=""
while IFS='|' read -r src dst; do
    case "$dst" in
        */shared|*/shared/) SHARED_HOST="$src"; SHARED_CONT="$dst"; break ;;
    esac
done < <(docker inspect "$VOYAGER_CONTAINER" \
            --format '{{range .Mounts}}{{.Source}}|{{.Destination}}{{"\n"}}{{end}}')

if [ -z "$SHARED_HOST" ]; then
    echo
    echo "  No '/shared' mount found on $VOYAGER_CONTAINER."
    echo "  Falling back to /tmp/hls, which only works if that container can"
    echo "  actually see the host's /tmp. If the inference tiles stay blank,"
    echo "  this is the first thing to check (see TROUBLESHOOTING.md)."
    echo
    SHARED_HOST="/tmp"
    SHARED_CONT="/tmp"
fi

SHARED_HLS_DIR="${SHARED_HOST%/}/hls"
SHARED_HLS_CONT="${SHARED_CONT%/}/hls"
log "host:      $SHARED_HLS_DIR"
log "container: $SHARED_HLS_CONT"

# The AI server runs as uid 1000 inside the container; the host dir is usually
# root-owned. Make it writable rather than failing silently at stream start.
step "Preparing HLS directories"
mkdir -p "$SHARED_HLS_DIR"
for slot in 2 3 4 5; do mkdir -p "$SHARED_HLS_DIR/slot-$slot"; done
chmod -R 777 "$SHARED_HLS_DIR" 2>/dev/null || \
    log "WARNING: could not chmod $SHARED_HLS_DIR — you may need sudo"
log "$SHARED_HLS_DIR ready"

# ── 6. Data directories ──────────────────────────────────────────────────────
step "Preparing data directories"
mkdir -p data/models data/recordings data/events data/uploads
# Backend runs as uid 1000 and must be able to write here.
chmod -R 777 data 2>/dev/null || true
log "data/ ready"

# ── 7. MediaMTX ──────────────────────────────────────────────────────────────
step "Checking MediaMTX"
if command -v mediamtx >/dev/null 2>&1; then
    log "mediamtx: $(command -v mediamtx)"
else
    echo
    echo "  mediamtx not found on PATH."
    echo "  It relays USB / video-file sources. RTSP cameras are read directly"
    echo "  and will work without it, but install it for full functionality:"
    echo "    https://github.com/bluenviron/mediamtx/releases  (linux_arm64v8)"
    echo
fi

# ── 8. USB camera ────────────────────────────────────────────────────────────
# A hard device mapping to a non-existent node makes the backend container
# refuse to start outright ("error gathering device information"). So the
# devices: block is commented out unless a camera is actually present.
step "Checking for a USB camera"

COMPOSE_FILE="docker-compose.yml"
if ls /dev/video* >/dev/null 2>&1; then
    CAM="$(ls /dev/video* | head -n 1)"
    log "found $CAM — enabling passthrough"
    python3 - "$COMPOSE_FILE" "$CAM" <<'PY'
import re, sys
path, cam = sys.argv[1], sys.argv[2]
src = open(path).read()
block = f"    devices:\n      - {cam}:{cam}\n"
src = re.sub(r'^    #? *devices:\n(?:^ *#? *- /dev/video.*\n)*',
             block, src, flags=re.M)
open(path, 'w').write(src)
PY
else
    log "no /dev/video* — USB features disabled (RTSP is unaffected)"
    python3 - "$COMPOSE_FILE" <<'PY'
import re, sys
path = sys.argv[1]
src = open(path).read()
src = re.sub(r'^    devices:\n(?:^ *- /dev/video.*\n)*',
             '    # devices:\n    #   - /dev/video0:/dev/video0\n', src, flags=re.M)
open(path, 'w').write(src)
PY
fi

# ── 9. Write .env ────────────────────────────────────────────────────────────
step "Writing .env"

[ -f .env.example ] || die ".env.example is missing."

# Preserve REGISTRY/TAG/TZ if the user already customised them.
OLD_REGISTRY=""; OLD_TAG=""; OLD_TZ=""
if [ -f .env ]; then
    OLD_REGISTRY="$(grep -E '^REGISTRY=' .env | cut -d= -f2- || true)"
    OLD_TAG="$(grep -E '^TAG=' .env | cut -d= -f2- || true)"
    OLD_TZ="$(grep -E '^TZ=' .env | cut -d= -f2- || true)"
    cp .env .env.bak
    log "existing .env backed up to .env.bak"
fi

cp .env.example .env

set_env() {  # set_env KEY VALUE
    local k="$1" v="$2"
    if grep -qE "^${k}=" .env; then
        # '|' delimiter: values contain '/' and ':'
        sed -i "s|^${k}=.*|${k}=${v}|" .env
    else
        printf '%s=%s\n' "$k" "$v" >> .env
    fi
}

set_env VOYAGER_CONTAINER "$VOYAGER_CONTAINER"
set_env VOYAGER_SDK_DIR   "$SDK_DIR"
set_env SHARED_HLS_DIR    "$SHARED_HLS_DIR"
[ -n "$OLD_REGISTRY" ] && set_env REGISTRY "$OLD_REGISTRY"
[ -n "$OLD_TAG" ]      && set_env TAG      "$OLD_TAG"
[ -n "$OLD_TZ" ]       && set_env TZ       "$OLD_TZ"

log ".env written"

# ── Summary ──────────────────────────────────────────────────────────────────
cat <<EOF

────────────────────────────────────────────────────────────
  Setup complete
────────────────────────────────────────────────────────────
  Voyager container : $VOYAGER_CONTAINER
  SDK path          : $SDK_DIR
  Metis driver      : $DRIVER_VER
  Shared HLS (host) : $SHARED_HLS_DIR
  AIPU cores        : 4
────────────────────────────────────────────────────────────
EOF
