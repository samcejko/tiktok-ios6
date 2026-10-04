#!/usr/bin/env python3
"""Tikie helper - the small service that runs on the Raspberry Pi.

It does the light work the iOS 6 app cannot: it asks yt-dlp for public TikTok video lists and fresh direct
URLs, and hands the app a tiny JSON. Video bytes normally stream straight from TikTok's CDN to the phone; only
the optional /proxy endpoint (used as a fallback and for "save") moves the actual video through the Pi.

No login, no posting - read only. yt-dlp is the maintained part: when TikTok changes, `pip install -U yt-dlp`
on the Pi fixes it without touching the app.

Endpoints (all JSON unless noted):
  GET /health
  GET /user?name=<handle>&count=30     a creator's recent videos (list of lightweight items)
  GET /resolve?id=<id|url>[&user=<handle>]  one video with a fresh playable URL and the headers to send
  GET /comments?id=<id|url>&count=40    top-level comments (best effort; empty if TikTok withholds them)
  GET /proxy?u=<playUrl>               streams the video bytes through the Pi (fallback / save); CDN hosts only
Set TIKIE_KEY to require ?k=<key> (or X-Tikie-Key header) on every call when you expose this beyond the LAN.
"""
import json
import os
import re
import sys
import time
import threading
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    import yt_dlp
except ImportError:
    sys.exit("tikie: yt-dlp is not installed (pip install yt-dlp)")

KEY = os.environ.get("TIKIE_KEY", "")
PORT = int(os.environ.get("TIKIE_PORT", "8730"))
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
      "Chrome/124.0.0.0 Safari/537.36")
CDN_HOST_RE = re.compile(r"\.(tiktokcdn[-\w]*\.com|tiktokv\.com|tiktok\.com|ttwstatic\.com|byteoversea\.com|ibyteimg\.com|akamaized\.net)$", re.I)

# --- tiny TTL cache -------------------------------------------------------

class TTLCache:
    def __init__(self):
        self._d = {}
        self._lock = threading.Lock()

    def get(self, key):
        with self._lock:
            item = self._d.get(key)
            if not item:
                return None
            if item[0] < time.time():
                self._d.pop(key, None)
                return None
            return item[1]

    def put(self, key, value, ttl):
        with self._lock:
            self._d[key] = (time.time() + ttl, value)

CACHE = TTLCache()

# --- yt-dlp helpers -------------------------------------------------------

_YDL_LOCK = threading.Lock()

def _ydl(opts):
    base = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "noplaylist": False,
        "http_headers": {"User-Agent": UA, "Referer": "https://www.tiktok.com/"},
        "extractor_args": {"tiktok": {"app_name": ["tiktok_web"]}},
    }
    base.update(opts)
    return yt_dlp.YoutubeDL(base)

def video_id(s):
    s = (s or "").strip()
    m = re.search(r"/video/(\d{6,25})", s)
    if m:
        return m.group(1)
    m = re.fullmatch(r"\d{6,25}", s)
    return m.group(0) if m else None

def norm_user(name):
    name = (name or "").strip().lstrip("@")
    return re.sub(r"[^A-Za-z0-9_.]", "", name)

def thumb_of(info):
    t = info.get("thumbnail")
    if t:
        return t
    thumbs = info.get("thumbnails") or []
    return thumbs[-1]["url"] if thumbs else None

def item_from_info(info):
    """A lightweight list item (no play URL - that is fetched lazily by /resolve)."""
    vid = str(info.get("id") or "")
    uploader = info.get("uploader") or info.get("creator") or info.get("channel") or ""
    return {
        "id": vid,
        "author": norm_user(uploader) or norm_user(info.get("uploader_id")),
        "authorName": info.get("uploader") or "",
        "desc": info.get("description") or info.get("title") or "",
        "cover": thumb_of(info),
        "duration": info.get("duration") or 0,
        "likes": info.get("like_count") or 0,
        "comments": info.get("comment_count") or 0,
        "plays": info.get("view_count") or 0,
        "url": info.get("webpage_url") or ("https://www.tiktok.com/@%s/video/%s" % (norm_user(uploader), vid) if uploader and vid else None),
    }

def user_list(name, count):
    name = norm_user(name)
    if not name:
        return []
    ckey = "user:%s:%d" % (name, count)
    cached = CACHE.get(ckey)
    if cached is not None:
        return cached
    url = "https://www.tiktok.com/@%s" % name
    opts = {"extract_flat": "in_playlist", "playlistend": max(1, min(count, 60))}
    with _YDL_LOCK, _ydl(opts) as ydl:
        info = ydl.extract_info(url, download=False)
    entries = info.get("entries") or []
    items = []
    for e in entries:
        if not e:
            continue
        it = item_from_info(e)
        if not it["author"]:
            it["author"] = name
        if it["id"]:
            items.append(it)
    CACHE.put(ckey, items, 600)
    return items

def _cookie_header(ydl, for_url):
    """TikTok's CDN URLs only serve to the session that resolved them: gather that session's TikTok cookies
    (ttwid etc.) so the player - or our /proxy - can send them."""
    host = urllib.parse.urlparse(for_url or "").hostname or ""
    parts = []
    try:
        for c in ydl.cookiejar:
            dom = (c.domain or "").lstrip(".")
            if dom and (host.endswith(dom) or "tiktok" in dom):
                parts.append("%s=%s" % (c.name, c.value))
    except Exception:
        pass
    return "; ".join(parts)

def resolve(ref, user=None):
    vid = video_id(ref)
    if not vid:
        raise ValueError("no video id")
    ckey = "resolve:%s" % vid
    cached = CACHE.get(ckey)
    if cached is not None:
        return cached
    if re.match(r"^https?://", ref or ""):
        url = ref
    elif user:
        url = "https://www.tiktok.com/@%s/video/%s" % (norm_user(user), vid)
    else:
        url = "https://www.tiktok.com/@_/video/%s" % vid   # TikTok redirects to the right handle
    with _YDL_LOCK, _ydl({"noplaylist": True}) as ydl:
        info = ydl.extract_info(url, download=False)
        play = info.get("url")
        fmts = info.get("formats") or []
        if not play and fmts:
            mp4s = [f for f in fmts if (f.get("ext") == "mp4" and f.get("url"))]
            mp4s.sort(key=lambda f: (f.get("tbr") or 0))
            play = (mp4s[-1] if mp4s else fmts[-1]).get("url")
        headers = {"User-Agent": UA, "Referer": "https://www.tiktok.com/"}
        if isinstance(info.get("http_headers"), dict):
            headers.update(info["http_headers"])
        cookie = _cookie_header(ydl, play)
        if cookie:
            headers["Cookie"] = cookie
    out = item_from_info(info)
    out["playUrl"] = play
    out["headers"] = headers
    out["width"] = info.get("width") or 0
    out["height"] = info.get("height") or 0
    out["music"] = (info.get("track") or info.get("artist") or "")
    if play:
        CACHE.put("hdr:" + play, headers, 1800)     # /proxy reuses the exact headers this URL needs
    CACHE.put(ckey, out, 1800)
    return out

def comments(ref, count):
    vid = video_id(ref)
    if not vid:
        return []
    ckey = "comments:%s:%d" % (vid, count)
    cached = CACHE.get(ckey)
    if cached is not None:
        return cached
    url = "https://www.tiktok.com/@_/video/%s" % vid
    opts = {"noplaylist": True, "getcomments": True,
            "extractor_args": {"tiktok": {"comment_count": [str(max(1, min(count, 100)))]}}}
    out = []
    try:
        with _YDL_LOCK, _ydl(opts) as ydl:
            info = ydl.extract_info(url, download=False)
        for c in (info.get("comments") or [])[:count]:
            out.append({"author": c.get("author") or "", "text": c.get("text") or "",
                        "likes": c.get("like_count") or 0})
    except Exception as e:
        sys.stderr.write("comments failed for %s: %s\n" % (vid, e))
    CACHE.put(ckey, out, 600)
    return out

# --- HTTP ----------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "tikie/1.0"

    def _send_json(self, obj, status=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _authorized(self, q):
        if not KEY:
            return True
        return q.get("k", [""])[0] == KEY or self.headers.get("X-Tikie-Key", "") == KEY

    def log_message(self, fmt, *args):
        sys.stderr.write("tikie %s - %s\n" % (self.address_string(), fmt % args))

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        q = urllib.parse.parse_qs(parsed.query)
        if path == "/health":
            return self._send_json({"ok": True, "ytdlp": getattr(yt_dlp.version, "__version__", "?")})
        if not self._authorized(q):
            return self._send_json({"error": "unauthorized"}, 401)
        try:
            if path == "/user":
                return self._send_json({"items": user_list(q.get("name", [""])[0], int(q.get("count", ["30"])[0]))})
            if path == "/resolve":
                ref = q.get("id", [""])[0] or q.get("url", [""])[0]
                return self._send_json(resolve(ref, q.get("user", [None])[0]))
            if path == "/comments":
                ref = q.get("id", [""])[0] or q.get("url", [""])[0]
                return self._send_json({"items": comments(ref, int(q.get("count", ["40"])[0]))})
            if path == "/proxy":
                return self._proxy(q.get("u", [""])[0])
        except ValueError as e:
            return self._send_json({"error": str(e)}, 400)
        except Exception as e:
            sys.stderr.write("tikie error on %s: %s\n" % (path, e))
            return self._send_json({"error": "upstream failed", "detail": str(e)[:200]}, 502)
        return self._send_json({"error": "not found"}, 404)

    def _proxy(self, u):
        if not u or not re.match(r"^https://", u):
            return self._send_json({"error": "bad url"}, 400)
        host = urllib.parse.urlparse(u).hostname or ""
        if not CDN_HOST_RE.search(host):
            return self._send_json({"error": "host not allowed"}, 403)
        hdrs = CACHE.get("hdr:" + u) or {"User-Agent": UA, "Referer": "https://www.tiktok.com/"}
        req = urllib.request.Request(u, headers=dict(hdrs))
        rng = self.headers.get("Range")
        if rng:
            req.add_header("Range", rng)
        try:
            up = urllib.request.urlopen(req, timeout=20)
        except Exception as e:
            return self._send_json({"error": "fetch failed", "detail": str(e)[:200]}, 502)
        self.send_response(up.status)
        for h in ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges"):
            v = up.headers.get(h)
            if v:
                self.send_header(h, v)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        if self.command == "HEAD":
            up.close()
            return
        try:
            while True:
                chunk = up.read(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            up.close()


def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    sys.stderr.write("tikie helper listening on :%d (key %s)\n" % (PORT, "set" if KEY else "off"))
    server.serve_forever()


if __name__ == "__main__":
    main()
