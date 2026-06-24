# Simple Player

A dead-simple macOS app for watching YouTube **distraction-free** — just the video, filling
the window. No title, no comments, no likes, no recommendations sidebar, no chrome. Like opening
a video in VLC, but it's YouTube and you're logged in.

## Why

YouTube's watch page is noise. Sometimes you just want to *watch the video*. This is a tiny
native app that lets you browse YouTube normally (logged in, with your home feed, subscriptions
and recommendations) and the moment you open a video it hands off to a clean native player with
nothing but the picture and auto-hiding controls.

## How it works

Two modes in one window:

- **Browse** — a `WKWebView` loaded with `youtube.com`, logged in with your account (the session
  persists across launches). Your home, recommendations, subscriptions, history — all normal.
- **Watch** — the instant the web view navigates to a video, the app intercepts it and plays the
  stream natively with `AVPlayer`. Zero YouTube UI. Move the mouse for native controls + a back
  button; they fade away on their own. `Esc` returns to the feed.

Streams are resolved with [`yt-dlp`](https://github.com/yt-dlp/yt-dlp): it picks H.264 video +
m4a audio (the codecs AVFoundation decodes reliably), which are merged on the fly with
`AVMutableComposition`. Your web-view cookies are passed to yt-dlp so personalized, private,
age-restricted and members-only videos work too.

## Requirements

- macOS 14+
- [`yt-dlp`](https://github.com/yt-dlp/yt-dlp): `brew install yt-dlp` (keep it updated with
  `yt-dlp -U` — YouTube changes formats and a stale yt-dlp stops resolving streams)
- Xcode 16+ to build

## Build & run

```bash
./build.sh            # builds Release → SimplePlayer.app in the project root
open ./SimplePlayer.app
```

Or open `SimplePlayer.xcodeproj` in Xcode and hit ⌘R.

> The app is signed to run locally only. The first launch may need **right-click → Open** to get
> past Gatekeeper.

## Auto-update

On launch the app checks the latest [GitHub release](https://github.com/zordor/simple-player/releases)
and, if a newer version exists, shows a discreet banner. One click downloads it, swaps the running
bundle and relaunches — no manual download. You can also check on demand with **⌘U**.

To cut a new release (bumps the version, builds, tags and publishes the binary):

```bash
./release.sh 1.2 "What changed"
```

## Shortcuts

| Key | Action |
|-----|--------|
| `⌘L` | Paste a YouTube URL to play it directly |
| `Esc` / `⌘[` | Back to the YouTube feed |
| `⌘U` | Check for updates |

## Known limitations

- **1080p H.264 ceiling.** AVFoundation can't decode YouTube's VP9/AV1 4K streams, so playback
  tops out at 1080p H.264. Still crisp; true 4K would need an external decoder and break the
  simplicity.
- Stream URLs expire after a few hours, so they're re-resolved each time you open a video.
- A few live/HLS streams may not merge in `AVMutableComposition` and fall back to a combined
  (~720p) stream.
- The YouTube login session expires periodically — just log back in inside the web view.

## License

MIT — see [LICENSE](LICENSE).
