# User Guide

How to use the dashboard once `./start.sh` has it running. Open **http://localhost** on the board, or `http://<board-ip>` from any machine on the same network.

The dashboard has four pages: **Live View**, **Recording**, **Playback**, and **Models**.

---

## 1. Deploy a model

Nothing will detect anything until a model is deployed. Do this first.

Go to **Models**. If a model is already listed as *deployed*, skip ahead.

To add one:

1. Click **Add Model**
2. Give it a name, upload the weights, and deploy
3. Wait — first-time deployment compiles the model for the AIPU and takes **10–15 minutes**. It only happens once per model.

### The one thing that catches everyone

A model YAML carries a **label filter**, which tells it which of the 80 COCO classes to keep. If that filter is set to a class that never appears in your scene, the model runs perfectly, detects nothing, and shows you a clean video with no boxes — and nothing anywhere says why.

If you have people in frame and no boxes appear, this is almost certainly the cause. Class `0` is `person`. Check that the filter includes it.

Confidence threshold matters too: the default `0.25` is sensible. Raise it for fewer, more certain boxes; lower it to catch small or partly hidden objects at the cost of false positives.

---

## 2. Add cameras and start streaming

Go to **Live View** → **RTSP**.

Enter a camera URL and click **Connect**, then **Add**. Repeat for up to four cameras. A typical URL:

```
rtsp://username:password@192.168.1.69:554/ch0_0.264
```

Both H.264 (`.264`) and H.265 (`.265`) cameras work, and you can mix them freely in one session.

Click **Start Stream**.

You get, per camera, a **raw tile** and an **inference tile** with boxes drawn on it. Three cameras gives you three of each.

### Getting your camera's URL right

The path varies by manufacturer — check the camera's manual or web UI. Common shapes:

| Vendor | Path |
|---|---|
| Hikvision | `/Streaming/Channels/101` |
| Dahua | `/cam/realmonitor?channel=1&subtype=0` |
| Generic | `/ch0_0.264`, `/stream1`, `/live` |

Test a URL from the board before putting it in the dashboard:

```bash
ffprobe -rtsp_transport udp "rtsp://user:pass@192.168.1.69:554/ch0_0.264"
```

If `ffprobe` cannot read it, the dashboard will not either. Two things to check:

- **The board must be able to reach the camera.** A camera on `192.168.0.x` is not reachable from a board on `192.168.1.x` without routing between them. `ping` it first.
- **Credentials must be in the URL**, `user:password@`, not left out.

A camera that is unreachable is marked *unreachable — retrying* on its tile and is retried in the background. The other cameras keep running, so one bad URL does not cost you the session.

---

## 3. Record

Go to **Recording**.

**Set the save folder first.** It must be a folder on the board that the container can write to. Create one:

```bash
mkdir -p ~/recordings
chmod 777 ~/recordings
```

Then enter `/home/<your-user>/recordings` and click **Save**.

Do not use `/home` itself — it is root-owned, the container runs as an unprivileged user, and the write will be refused.

Now start a recording. You get a **Raw Feeds** column and an **Inference Feeds** column, one row per camera. Hit **Record** on whichever you want. They run independently, so you can record raw camera 1 and annotated camera 2 at the same time if you like.

Files land in your save folder, named:

```
20260714-093045_cam1_raw.mp4
20260714-093102_cam2_inference.mp4
```

Raw recordings are copied straight from the camera, so they keep the camera's full resolution and framerate with no quality loss and almost no CPU cost. Annotated recordings come out at 720p / 8 fps with the boxes burnt in.

---

## 4. Play back

Go to **Playback**. Recordings are listed with a camera and type badge. Click one to play it; drag to seek.

---

## Reading the live view

The header tells you the state of the session:

```
3 cameras running the same model — raw + inference tile per camera
RTSP • 3 cameras • 6 tiles active
```

Click the ⤢ icon on any tile to expand it.

**On latency.** The live tiles should be under a second behind reality. The easiest way to check is a camera that burns a timestamp into the picture: compare it with the board's clock.

```bash
date
```

Note the board typically runs on **UTC** while cameras are usually set to local time, so subtract the offset before you panic. In India, for instance, the burnt-in timestamp will read 5 hours 30 minutes ahead of `date`.

If the gap is genuinely large and *growing*, something is wrong — see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

## How many cameras can it take?

Four is the supported maximum.

The AIPU is a single device shared by every camera in the session, so throughput divides between them: more cameras means fewer frames per second each. With all four cores in use there is comfortable headroom for four cameras at typical IP-camera framerates.

You will feel it as a lower framerate per tile, not as growing delay. If the delay itself starts increasing, that is a fault, not a limit.

---

## FAQ

**Can different cameras run different models?**
Not yet. One model runs across all cameras in a session.

**Can I use a USB webcam?**
Yes. Plug it in *before* running `./start.sh` — the setup script detects it and wires it through. If you plug it in afterwards, just re-run `./start.sh`.

**Can I use a video file?**
Yes — the **Video File** tab on Live View.

**Where do recordings go?**
The folder you set on the Recording page. It is a path on the board, not inside a container.

**Do I have to redeploy the model every time?**
No. Deployment is once per model; it survives restarts.

**The video is timestamped hours away from the real time.**
The board is on UTC and your camera is on local time. Set `TZ` in `.env` if you want them to agree.
