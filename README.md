<p align="center">
  <img src="icon/Icon-round.png" alt="FlashLyrics Logo" width="120" height="120" />
</p>

# FlashLyrics

> **Google Play Alpha Testing**: Join the Google group first:- https://groups.google.com/g/flashlryics  
> Then opt for testing and download here: https://play.google.com/apps/testing/music.flashlyrics.app

Android app that detects what song you're playing and shows the lyrics. Works with Spotify, YouTube Music, Apple Music, JioSaavn, Gaana, SoundCloud, and pretty much any music app.

<p align="center">
  <a href="https://buymeacoffee.com/avaneeshinamdar" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="42"></a>
  &nbsp;&nbsp;
  <a href="#" target="_blank"><img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" alt="Get it on Google Play" height="42"></a>
</p>

## Features


### Light & Dark Mode

Fully supports light and dark themes so it looks great no matter your preference.

<p align="center">
  <img src="Images/Light%20and%20Dark%20Mode.jpeg" alt="Light and Dark Mode" width="250" />
</p>

### Offline Library

All lyrics you've viewed are cached locally. Access your entire library offline — instantly.

<p align="center">
  <img src="Images/Library1.jpeg" alt="Lyrics Library" width="250" />
</p>

### Manual Search

Can't find a song automatically? Search for any song by title or artist and get lyrics instantly.

<p align="center">
  <img src="Images/Search%20Feature.jpeg" alt="Search Feature" width="250" />
</p>

### Accent Color Customization

Personalize the app with your choice of accent colors to match your style.

<p align="center">
  <img src="Images/AccentColor.jpeg" alt="Accent Color Customization" width="250" />
</p>

### Synced Lyrics with Tap-to-Seek

Real-time synced lyrics that scroll automatically with the music. Tap on any lyric line to jump to that part of the song - just like your favorite streaming apps!

### Song Controls

Control playback directly from the app with the built-in seek bar. Play, pause, and seek to any position in the song without switching apps.

### Lyrics Sync Offset

Adjust the lyrics timing if they appear too early or late. Perfect for songs with unusual timing or when the sync is slightly off.

### More

- **Auto-detects** the currently playing song using Android's MediaSession
- **Synced lyrics** that scroll in real time (falls back to plain lyrics)
- **Tap on lyrics** to seek to that position in the song
- **Playback controls** with seek bar for manual song navigation
- Pulls lyrics from **6 different sources** — LRCLIB, Textyl, ChartLyrics, Lyrics.ovh, Lyrist, NetEase
- **Share lyrics** as a styled image or plain text
- **Album art** pulled from the playing app
- Works with **Hindi, Japanese, Korean, Chinese** songs (NetEase covers Asian music well)

## Supported music apps

Spotify, YouTube Music, Apple Music, Amazon Music, SoundCloud, Deezer, Tidal, JioSaavn, Gaana, Wynk Music, Hungama, Resso, Musixmatch, Samsung Music, Mi Music, PowerAmp, VLC, Foobar, and 40+ more. If the app exposes a MediaSession, FlashLyrics will probably pick it up.

## Permissions

- **Notification Access** — required to detect what's playing. The app reads media notifications to get song title/artist. That's it.


## Lyrics sources

| Source | Type | Coverage |
|--------|------|----------|
| LRCLIB | Synced (LRC) | Best for timed lyrics |
| Textyl | Synced (LRC) | Good backup for synced |
| ChartLyrics | Plain | Large English catalog |
| Lyrics.ovh | Plain | Reliable fallback |
| Lyrist | Plain | Additional backup |
| NetEase | Plain | Strong for Asian music |

All sources are free and don't require API keys.