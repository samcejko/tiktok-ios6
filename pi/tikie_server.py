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
  GET /resolve?id=<id|url>[&user=<handle>][&vcodec=h264][&maxh=1280]  one video with a fresh playable URL and
                                       the headers to send; an H.264 rendition by default (iOS 6 has no HEVC decoder)
  GET /comments?id=<id|url>&count=40    top-level comments (best effort; empty if TikTok withholds them)
  GET /proxy?u=<playUrl>               streams the video bytes through the Pi (fallback / save); CDN hosts only
  GET /yt/resolve?id=<youtube id|url>  fresh YouTube stream URLs for the Tubie app (see the YouTube section)
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

def _long_side(f):
    return max(f.get("width") or 0, f.get("height") or 0)

def pick_format(info, vcodec, maxh):
    """TikTok serves each video as h265 (bytevc1) and usually also as h264. yt-dlp's default pick prefers h265,
    which iOS 6 cannot decode (the sound plays over a black picture), so choose an h264 rendition: the largest whose
    long side fits maxh (the device's screen), else the smallest above it. The watermarked "download" file is h264
    too and is the last resort. None = no preference or nothing suitable: the caller keeps yt-dlp's pick."""
    if vcodec != "h264":
        return None
    fmts = [f for f in (info.get("formats") or []) if f.get("url")]
    h264 = [f for f in fmts if (f.get("vcodec") or "").lower().startswith(("h264", "avc"))]
    cands = [f for f in h264 if f.get("format_id") != "download"] or h264
    if not cands:
        return None
    sized = [f for f in cands if _long_side(f) > 0]
    fit = [f for f in sized if _long_side(f) <= maxh]
    if fit:
        return max(fit, key=lambda f: (_long_side(f), f.get("tbr") or 0))
    if sized:
        return min(sized, key=lambda f: (_long_side(f), -(f.get("tbr") or 0)))
    return cands[0]

def resolve(ref, user=None, vcodec="h264", maxh=1280):
    vid = video_id(ref)
    if not vid:
        raise ValueError("no video id")
    ckey = "resolve:%s:%s:%d" % (vid, vcodec, maxh)
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
        chosen = pick_format(info, vcodec, maxh)
        if chosen:
            play = chosen.get("url")
        else:
            play = info.get("url")
            fmts = info.get("formats") or []
            if not play and fmts:
                mp4s = [f for f in fmts if (f.get("ext") == "mp4" and f.get("url"))]
                mp4s.sort(key=lambda f: (f.get("tbr") or 0))
                play = (mp4s[-1] if mp4s else fmts[-1]).get("url")
        headers = {"User-Agent": UA, "Referer": "https://www.tiktok.com/"}
        if isinstance(info.get("http_headers"), dict):
            headers.update(info["http_headers"])
        if chosen and isinstance(chosen.get("http_headers"), dict):
            headers.update(chosen["http_headers"])
        cookie = _cookie_header(ydl, play)
        if cookie:
            headers["Cookie"] = cookie
    src = chosen or info
    out = item_from_info(info)
    out["playUrl"] = play
    out["headers"] = headers
    out["width"] = src.get("width") or 0
    out["height"] = src.get("height") or 0
    out["vcodec"] = src.get("vcodec") or ""
    out["formatId"] = src.get("format_id") or ""
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

# --- YouTube (added for the Tubie iOS 6 app; everything above is unchanged) ------
# Gives the phone a fresh, playable YouTube stream so it can get past the ~60 s PO-token wall that caps the
# adaptive files when the device fetches them itself. Returns the best progressive MP4 (<=720p, H.264+AAC, plays
# straight away on iOS 6) plus the best adaptive H.264 video and AAC audio (for a later 1080p remux in the app).

YT_UA = ("com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3 like Mac OS X)")

def yt_video_id(s):
    s = (s or "").strip()
    m = re.search(r"(?:v=|/shorts/|/embed/|youtu\.be/|/v/|/live/)([A-Za-z0-9_-]{11})", s)
    if m:
        return m.group(1)
    return s if re.fullmatch(r"[A-Za-z0-9_-]{11}", s) else None

def _ydl_yt(opts):
    # yt-dlp's default player clients return the full H.264 DASH ladder (itags 133-137 etc.) with direct URLs;
    # forcing ios/web cut it down to the 360p progressive only, so leave the clients at their defaults.
    base = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "noplaylist": True,
        # a permissive selector so extract_info never fails on "no requested format" (we read info["formats"]
        # ourselves anyway, and the container has no ffmpeg to merge a video+audio pick)
        "format": "bv*+ba/b/bv*/ba",
        "ignore_no_formats_error": True,
    }
    base.update(opts)
    return yt_dlp.YoutubeDL(base)

def _yt_pick(fmts, want):
    """want: 'prog' (video+audio mp4 <=720), 'video' (avc1 video-only <=1080), 'audio' (m4a audio-only)."""
    out = []
    for f in fmts:
        if not f.get("url"):
            continue
        va = f.get("vcodec") not in (None, "none")
        aa = f.get("acodec") not in (None, "none")
        vc = f.get("vcodec") or ""
        h = f.get("height") or 0
        if want == "prog":
            if not (va and aa and (f.get("ext") == "mp4") and vc.startswith("avc") and (h == 0 or h <= 720)):
                continue
        elif want == "video":
            if not (va and not aa and vc.startswith("avc") and (h == 0 or h <= 1080)):
                continue
        elif want == "audio":
            ac = f.get("acodec") or ""
            if not (aa and not va and (ac.startswith("mp4a") or f.get("ext") == "m4a")):
                continue
        out.append(f)
    if want == "audio":
        out.sort(key=lambda f: (f.get("abr") or f.get("tbr") or 0))
    else:
        out.sort(key=lambda f: ((f.get("height") or 0), (f.get("tbr") or 0)))
    return out[-1] if out else None

def _yt_headers(info, f):
    h = {"User-Agent": YT_UA}
    if isinstance(info.get("http_headers"), dict):
        h.update(info["http_headers"])
    if isinstance(f.get("http_headers"), dict):
        h.update(f["http_headers"])
    return h

def resolve_yt(ref):
    vid = yt_video_id(ref)
    if not vid:
        raise ValueError("no youtube video id")
    ckey = "yt:%s" % vid
    cached = CACHE.get(ckey)
    if cached is not None:
        return cached
    url = "https://www.youtube.com/watch?v=%s" % vid
    with _YDL_LOCK, _ydl_yt({}) as ydl:
        info = ydl.extract_info(url, download=False)
    fmts = info.get("formats") or []
    # A map itag -> fresh direct URL for every format served straight over https (the DASH ladder 133-137 etc. and
    # the audio 139/140), skipping HLS. Tubie keeps the sidx byte ranges it already got from its own InnerTube for
    # each itag and just swaps in these URLs, so the proxy can remux the whole video (no 60 s PO-token wall).
    formats = {}
    audio_pick = {}   # base itag -> (score, url): for dubbed videos keep only the original/default track
    for f in fmts:
        u = f.get("url")
        if not u or (f.get("protocol") or "") not in ("https", "http"):
            continue   # skip m3u8/HLS; we want the directly-ranged files
        fid = str(f.get("format_id") or "")
        base = fid.split("-")[0]   # multi-language audio comes as "140-0".."140-19"
        if not base.isdigit():
            continue
        is_audio = f.get("acodec") not in (None, "none") and f.get("vcodec") in (None, "none")
        if is_audio and "-" in fid:
            # the app's sidx ranges are for the ORIGINAL audio, so pick the track yt-dlp marks default/original
            score = f.get("language_preference") or -1
            note = (f.get("format_note") or "").lower()
            if "default" in note or "original" in note:
                score += 1000
            if base not in audio_pick or score > audio_pick[base][0]:
                audio_pick[base] = (score, u)
        else:
            formats[base] = u
    for base, (score, u) in audio_pick.items():
        formats.setdefault(base, u)
    prog = _yt_pick(fmts, "prog")
    out = {
        "id": vid,
        "title": info.get("title") or "",
        "duration": info.get("duration") or 0,
        "isLive": bool(info.get("is_live")),
        "formats": formats,
    }
    if prog:
        out["playUrl"] = prog.get("url")
        out["playHeight"] = prog.get("height") or 0
        out["playItag"] = str(prog.get("format_id") or "")
    CACHE.put(ckey, out, 3600)   # googlevideo URLs last ~6 h; refresh well before that
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
        if path == "/health" or path == "/yt/health":
            return self._send_json({"ok": True, "ytdlp": getattr(yt_dlp.version, "__version__", "?")})
        if not self._authorized(q):
            return self._send_json({"error": "unauthorized"}, 401)
        try:
            if path == "/user":
                return self._send_json({"items": user_list(q.get("name", [""])[0], int(q.get("count", ["30"])[0]))})
            if path == "/resolve":
                ref = q.get("id", [""])[0] or q.get("url", [""])[0]
                # what the device can show; app builds that send nothing get the iOS 6 defaults
                vcodec = (q.get("vcodec", ["h264"])[0] or "h264").lower()
                try:
                    maxh = int(q.get("maxh", ["1280"])[0])
                except ValueError:
                    maxh = 1280
                maxh = max(240, min(maxh, 4096))
                return self._send_json(resolve(ref, q.get("user", [None])[0], vcodec, maxh))
            if path == "/yt/resolve":
                return self._send_json(resolve_yt(q.get("id", [""])[0] or q.get("url", [""])[0]))
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
