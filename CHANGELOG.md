# Changelog

## 0.1.0 (2026-10-04)

First version.

- A vertical, full-screen "For You" feed: videos from all of TikTok's Explore topics, picked by a taste the app
  learns on the device (watch time, saves, "Not interested"; it keeps trying new topics). No following, no preset
  creators. "What it learned" shows the topics, likes and dislikes and can forget them; videos can be limited to
  chosen languages; fresh videos are preferred
- Starts at once (the next video is buffered ahead), double tap saves, hold for a menu (2x speed, Not interested,
  copy link), drag along the bottom edge to seek
- Photo posts (slideshows), comments with their replies, creator profiles with their posts
- Landscape iPad: the comments sit beside the video
- TikTok LIVE: a list of live creators, the LIVE badge on a creator's picture, their profile and live links; the FLV
  stream is repacked on the device into HLS (and pulled again whenever TikTok's CDN ends it)
- Links: `tikie:open?url=`, "Open a link"; Surfari offers TikTok links to Tikie
- Save videos for yourself
- Video streams straight from TikTok's CDN through the app's own TLS layer; the Pi helper only finds the videos
- Needs the `tikie` helper (yt-dlp) on your own server; set its address and key in Settings
