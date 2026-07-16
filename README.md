# WGtech AI Starter Kit — Metis Compute Board (Dashboard)

This Starter Kit empowers university students, researchers, and enthusiasts to explore Edge AI through a complete platform for computer vision development and deployment. It runs on the **Axelera Metis Compute Board** — an RK3588 single-board computer with an integrated 4-core Metis AIPU — and lets you run, compare, and analyse Vision AI models on live cameras, entirely from a browser.

> **Different board?** This kit is for the **Metis Compute Board**. If you have the **Raspberry Pi 5 + Metis M.2** unit, use [WG-Tech-Solutions/Starter-Kit](https://github.com/WG-Tech-Solutions/Starter-Kit) instead.

---

## 🚀 Getting Started — Follow These Steps

### Step 1 — Clone this repo

Run this on your **Desktop/Laptop** terminal:

```
git clone https://github.com/WG-Tech-Solutions/Starter-Kit-Advanced.git
cd Starter-Kit-Advanced
```

### Step 2 — Open SBCstarterpack.html

Inside the cloned folder you will find `SBCstarterpack.html`. Open it in a browser on your desktop or laptop — it walks you through everything on the board:

* Flashing the OS
* Installing Docker
* Installing the Axelera Metis driver
* Installing the Voyager SDK container
* Confirming AI inference is working on the AIPU

This takes a total of 2–4+ hours (active setup time: 30–60 mins). **Do not run any scripts in this repo until you have finished the HTML guide.**

### Step 3 — Come back here

Return after you have:

* Completed all sections of `SBCstarterpack.html`
* Seen FPS output from `./inference.py yolov8n-coco media/traffic1_1080p.mp4` inside the Voyager-SDK container

---

## Prerequisites — verify before running start.sh

Run in the **Metis Compute Board** terminal:

**1. OS is 64-bit / RK3588**

```
uname -m                      # aarch64
cat /proc/device-tree/model   # ...RK3588...
```

**2. Docker working (without sudo)**

```
docker run hello-world
```

**3. Metis driver loaded**

```
lsmod | grep metis
cat /sys/module/metis/version
```

**4. Voyager-SDK container exists**

```
docker ps -a | grep -i voyager
```

**5. Inference confirmed working** — you ran `./inference.py` inside the Voyager-SDK container and saw FPS output.

---

## File overview

```
Starter-Kit-Advanced/
├── SBCstarterpack.html   ← hardware setup guide — start here
├── README.md             ← this file
├── USER_GUIDE.md         ← how to use the dashboard after setup
├── start.sh              ← main entry point — run this every time
├── stop.sh               ← cleanly stops all services
├── start_voyager.sh      ← starts Voyager-SDK container + MediaMTX
├── setup.sh              ← installs MediaMTX, builds .env, handles USB camera
├── docker-compose.yml    ← frontend + backend containers (pulled, not built)
├── voyager-service/
│   ├── ai_server.py      ← FastAPI server inside Voyager-SDK
│   ├── ai_inference.py   ← inference session management
│   ├── inference_runner.py
│   └── wginference.py    ← AIPU inference wrapper
└── data/                 ← created automatically on first run
    ├── recordings/
    ├── uploads/
    ├── models/
    └── hls/
```

As with the Pi kit, the **frontend and backend are pulled as pre-built container images** (there is no `frontend/` or `backend/` source here). The **inference service** (`voyager-service/`) ships as source because it is copied into Axelera's Voyager-SDK container at start.

---

## First-time setup

### Step 1 — Make scripts executable

```
cd ~/Starter-Kit-Advanced
chmod +x start.sh stop.sh start_voyager.sh setup.sh
```

### Step 2 — Load the kernel module

Required every reboot:

```
sudo modprobe metis
lsmod | grep metis   # should show metis in output
```

### Step 3 — (Optional) Connect USB camera

Plug it in **before** running `start.sh`. The setup script detects it automatically. If you plug it in later, just re-run `./start.sh`.

### Step 4 — Run start.sh

```
./start.sh
```

This does four things in order:

1. **setup.sh** — installs MediaMTX (first time only), creates `.env`, sets up data directories, detects the Voyager-SDK container and USB camera
2. **start_voyager.sh** — starts MediaMTX, starts the Voyager-SDK container, copies the service files in, detects the container IP, updates `.env`, starts `ai_server.py`
3. **docker compose up** — **pulls** and starts the frontend and backend containers
4. **Health check** — waits for the backend to report healthy

When it finishes you will see:

```
╔══════════════════════════════════════════════════════════╗
║  ✓  WGtech AI Dashboard is running                       ║
╠══════════════════════════════════════════════════════════╣
║  Dashboard:      http://localhost                        ║
║  Backend API:    http://localhost/api                    ║
╚══════════════════════════════════════════════════════════╝
```

Open a browser and go to **http://localhost**.

Before exploring the dashboard, read [USER_GUIDE.md](USER_GUIDE.md) to understand the application's features, usage, and FAQs.

---

## Every boot — what to run

```
sudo modprobe metis
./start.sh
```

---

## USB camera behaviour

`setup.sh` checks for `/dev/video0` on every run and automatically updates `docker-compose.yml`:

| Camera state | What happens |
| --- | --- |
| Plugged in before `./start.sh` | Detected, passed through to backend, full USB features available |
| Not plugged in | Warning printed, USB features disabled in dashboard |
| Plugged in after containers started | Run `./start.sh` again |

> **Do not edit the `devices:` block in `docker-compose.yml` manually** — it is managed by `setup.sh`. A hard mapping to a missing device makes the backend refuse to start.

---

## Stopping everything

```
./stop.sh
```

This stops inference sessions, `ai_server.py`, the dashboard containers, and MediaMTX in the correct order.

---

## Useful commands

```
# Dashboard backend logs
docker compose logs -f backend

# Voyager SDK / inference server logs
docker exec Voyager-SDK tail -f /tmp/ai_server.log

# What is running on the AIPU
docker exec Voyager-SDK curl -s http://localhost:8001/inference/status

# Check running containers
docker ps

# Restart everything
./stop.sh && ./start.sh
```

---

## Troubleshooting

### Dashboard won't load at http://localhost

```
docker compose ps
docker compose logs backend --tail=30
```

A common cause is a USB camera mapped in `docker-compose.yml` that is not plugged in — re-run `./setup.sh`, which handles it.

### Streams run but there are no boxes

Almost always the model's **label filter** is set to a class not in your scene, so every detection is discarded silently. Class `0` is `person` — make sure the filter includes what you want to detect.

### The AIPU seems slow (~17 fps)

The model is using one of the board's **four** AIPU cores. The kit forces all four; if testing `inference.py` directly, add `--aipu-cores 4`.

### Latency grows over a long session

Usually stacked sessions competing for the AIPU. `./stop.sh && ./start.sh` clears it.

### axdevice shows no devices

```
sudo modprobe metis
lsmod | grep metis
```

If it persists, **power-cycle** the board (not just reboot).

---

## For More Information and References

Axelera documentation: https://docs.axelera.ai/

Axelera Voyager SDK: https://github.com/axelera-ai-hub/voyager-sdk

Raspberry Pi 5 edition of this kit: https://github.com/WG-Tech-Solutions/Starter-Kit

## License

MIT — see [LICENSE](LICENSE).
