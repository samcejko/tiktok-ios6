# Tikie helper (Raspberry Pi)

The small service the iOS 6 app (Tikie) talks to. It runs `yt-dlp` to get public TikTok video lists and fresh
direct URLs and returns tiny JSON. Video normally streams straight from TikTok's CDN to the phone; only `/proxy`
moves the bytes through the Pi (fallback and "save"). Read-only: no login, no posting.

## Run

```sh
docker compose up -d --build        # builds the image, starts tikie on :8730
curl http://<pi>:8730/health
curl "http://<pi>:8730/user?name=tiktok&count=10"
```

## Keep it working

TikTok changes often; `yt-dlp` is the maintained piece. When something stops resolving:

```sh
docker compose build --no-cache && docker compose up -d     # rebuild with the latest yt-dlp
```

## Exposing beyond the LAN

Set `TIKIE_KEY` in `docker-compose.yml`; the app must then send `?k=<key>`. Point your existing
nginx/cloudflared at `http://127.0.0.1:8730`. The app's "server" setting takes the base URL (and key).

## Endpoints

| path | returns |
|------|---------|
| `/health` | `{ok, ytdlp}` |
| `/user?name=&count=` | `{items:[{id,author,desc,cover,duration,likes,comments,plays,url}]}` |
| `/resolve?id=&user=` | one item plus `playUrl`, `headers`, `width`, `height`, `music` |
| `/comments?id=&count=` | `{items:[{author,text,likes}]}` (best effort) |
| `/proxy?u=` | the video bytes (TikTok CDN hosts only), Range supported |
