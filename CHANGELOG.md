# Changelog

## 0.2.0 (2026-10-05)

- Search (the magnifier on the feed): TikTok's suggestions while typing, recent searches, results as videos,
  creators, hashtags and sounds; `#name` and `@name` open the hashtag or the creator at once
- #hashtags and @mentions in a video's caption are tappable; a hashtag's page shows its counts and its videos
- Sounds: the music line and the spinning disc open the sound's page - hear it, see the videos that use it
- Creator pages are full pages now (they slide in from the side, with Back): following, followers and likes, bio,
  link, and their posts page on as you scroll; swipe a video to the left for its creator
- Comments slide up from the bottom over the video (it plays on), with pictures, names, time and likes
- TikTok's captions over the videos that have them (your language when TikTok translated it); on/off in the hold
  menu and in Settings
- At the first start, pick a few topics so the feed hits the mark from the first videos (Settings: Pick topics)
- Videos opened from a page (a hashtag, a sound, a profile, search) play on into that page's next videos
- Auto-advance is off by default (the video loops until you swipe); the button with the two arrows is gone - "Open
  in Surfari" is in the hold menu next to "Copy link"
- Fixes: a video that ran out of data on slow Wi-Fi now plays on by itself; the feed no longer jumps back when it
  loads more videos during a swipe; a video comes back where it was after a profile or a live stream
- New icon: a note
- The helper (`pi/tikie_server.py`) has /search, /suggest, /tag, /sound and /posts, captions and comment pictures

## 0.1.0 (2026-10-04)

First version, in English and Czech. Named TikTak (it was Tikie while it was being built).

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
- Links: `tiktak:open?url=` (also `tikie:`), "Open a link"; Surfari offers TikTok links to TikTak
- Save videos for yourself
- Video streams straight from TikTok's CDN through the app's own TLS layer; the Pi helper only finds the videos
- Needs its helper (the `tikie` service, yt-dlp) on your own server; set its address and key in Settings
