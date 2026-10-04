# Tikie - TikTok on iOS 6

An unofficial TikTok **viewer** for jailbroken iOS 6.x (iPad 2 / iPhone 4S era). A vertical, full-screen feed of
public videos from the creators you follow, ordered by your own local ranking (what you finish or save rises,
what you skip falls). You can watch, read comments and save videos for yourself. Read-only: no login, no likes,
no posting.

Tikie is not affiliated with, endorsed by or associated with TikTok or ByteDance. It only reads public content.

## How it works (and why it needs your own server)

TikTok's app API is locked behind request signing that cannot be reproduced on iOS 6, so Tikie does not talk to
TikTok directly for the lists. Instead a tiny helper, **tikie**, runs on your own machine (a Raspberry Pi is
perfect) and uses the maintained `yt-dlp` to fetch public video lists and fresh direct URLs. The app asks the
helper for a little JSON; the **video itself streams straight from TikTok's CDN to the device** through Tikie's
own TLS layer (iOS 6 cannot talk to modern servers otherwise). Away from home, or if a direct URL is refused, the
helper can also stream the bytes itself.

So: one small service on your server, and the app is a thin, private client. When TikTok changes something, you
update `yt-dlp` on the server - the app does not need rebuilding.

See `pi/README.md` to run the helper (Docker). Then in the app: Settings - the gear on the feed - set the server
address (e.g. `https://ytdlp.samcejko.eu`) and, if you set one, the key. Add a creator and the feed fills up.

## Installing on the device

The IPA installs with `ipainstaller -f Tikie-<version>.ipa` (AppSync Unified), or the DEB with `dpkg -i` then
`su mobile -c uicache`. Either works. Do not keep both installed at once.

## Project layout

```
pi/           the helper that runs on your server (Python + yt-dlp, Docker)
src/TikTok    the data layer: models, the client that talks to the helper, the local "For You" ranking, keychain
src/Net       TLS socket, HTTP client, image loader, the media proxy that feeds AVPlayer (shared with the family)
src/UI        the vertical feed and player, creators, saved, comments, settings
src/Util      formatting, settings, device helpers
tools         push/build/release/device scripts, icon, asset generator
vendor        mbedTLS configuration and glue (the library is fetched by CI)
```

## Privacy

Your creators, saved videos and taste live on the device. The app talks only to your own helper and to TikTok's
public CDN. No account, no telemetry.

## License

MIT, see `LICENSE`. Third-party notices in `THIRD-PARTY-NOTICES.md`.
