# FlashLyrics

Real-time lyrics for any song playing on your phone.

FlashLyrics automatically detects what's playing on Spotify, YouTube Music, or any other music app and shows you the lyrics instantly. No more switching apps or manual searching.

## Features

- **Auto Detection** – Detects songs automatically from any music player
- **Synced Lyrics** – Lyrics scroll with the music in real-time (Apple Music/Spotify style)
- **Adjustable Text Size** – Customize synced lyrics font size with an easy slider
- **Offline Support** – Saves lyrics locally so you don't need internet every time
- **Multi-Source** – Searches LRCLIB, Textyl, and other providers for best results
- **Wide Compatibility** – Works with Spotify, YouTube Music, Apple Music, JioSaavn, Gaana, and more

## Screenshots

*Coming soon*

## How it works

When you enable notification access, the app can see media notifications from your music players. It picks up the song title and artist, then searches for lyrics across multiple sources. Synced lyrics get priority when available.

The lyrics are cached locally so if you play the same song again, it loads instantly.

## Tech Stack

- **Framework:** Flutter/Dart
- **State Management:** Riverpod
- **Architecture:** Clean Architecture (data/domain/presentation layers)
- **Native:** Kotlin for Android MediaSessionManager integration

## Privacy

- No accounts or tracking
- No data sent to third party analytics
- Only permission needed is notification access (to detect songs)
- Everything is stored locally on your device

---

Built by Avaneesh
