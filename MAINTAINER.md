# Maintainer Notes

Students never read this. It covers the one-time work that makes the kit pullable.

## The model (same as the Pi kit)

- **frontend + backend** → pre-built images, **pulled** by `docker compose up`.
  No source for these lives in this public repo.
- **voyager-service** → ships as source (`voyager-service/*.py`), because it is
  copied into Axelera's Voyager-SDK container at start.
- **scripts + compose + docs** → in this repo, cloned by the student.

So before students can use the repo, the two images must exist in a registry the
students can pull from.

## One-time: build and push the frontend & backend images

From your **private** source repo (the one with `frontend/` and `backend/`), on the
board (arm64):

```bash
REGISTRY=wgtechsolutions1
TAG=latest

# frontend
docker build -t $REGISTRY/sbc-dashboard-frontend:$TAG ./frontend
docker push $REGISTRY/sbc-dashboard-frontend:$TAG

# backend
docker build -t $REGISTRY/sbc-dashboard-backend:$TAG ./backend
docker push $REGISTRY/sbc-dashboard-backend:$TAG
```

Then make **both repositories public** on Docker Hub:
hub.docker.com → each repository → **Settings** → **Visibility → Public**.

If they stay private, students would need `docker login` first.

> Not using GHCR? Any registry works — Docker Hub, etc. Just set `REGISTRY`
> accordingly here and in `docker-compose.yml` / `.env.example`
> (e.g. `REGISTRY=yourdockerhubname`, images then `yourdockerhubname/sbc-dashboard-backend`).

## Building arm64 from an x86 machine

The board is aarch64. Build on the board, or:

```bash
docker buildx build --platform linux/arm64 \
  -t $REGISTRY/sbc-dashboard-backend:$TAG --push ./backend
```

## Keeping the repos in sync

| Change | Action |
|---|---|
| frontend/backend code | rebuild + push those images |
| voyager-service code | commit the `.py` to this public repo |
| scripts / compose / docs | commit to this public repo |
| A new env var | add to `.env.example` **and** the code that reads it |

## About `start_voyager.sh`

This is the real script from the source repo, with board auto-detection (Metis
Compute Board vs Pi). It reads `voyager-service/*.py` from **this repo** (they're
committed here) and copies them into the Voyager-SDK container — no image pull
needed for the service, exactly like the Pi kit.

## Note on source exposure

This mirrors the Pi kit: the inference service source is public, and the
frontend/backend ship as images (which can still be extracted by anyone who pulls
them — image distribution is not a source-hiding guarantee). If you later need the
service hidden too, that's a different distribution model (private registry +
payload image) — ask and it can be set up.
