# FlashLyrics

Real-time lyrics for any song playing on your phone.

FlashLyrics automatically detects what's playing on Spotify, YouTube Music, or any other music app and shows you the lyrics instantly. No more switching apps or manual searching.

## What it does

- Detects songs automatically from any music player
- Shows synced lyrics that scroll with the music (when available)
- Falls back to plain lyrics when synced versions aren't found
- Saves lyrics offline so you don't need internet every time
- Works with Spotify, YouTube Music, Apple Music, and basically every music app

## Screenshots

*Coming soon*

## Getting Started

### Download

Grab the latest APK from the [Releases](https://github.com/Avaneesh-Inamdar/FlashLyrics/releases) page.

### First time setup

1. Install the APK
2. Open FlashLyrics
3. Grant notification access when prompted (this is how the app reads what song is playing)
4. Play some music and watch the lyrics appear

That's it. No account needed. No sign up. Just lyrics.

## Building from source

If you want to build it yourself:

```bash
git clone https://github.com/Avaneesh-Inamdar/FlashLyrics.git
cd FlashLyrics/lyricx
flutter pub get
flutter run
```

Requirements:
- Flutter 3.11+
- Android SDK with API 26+ (Android 8.0)

For a release build:
```bash
flutter build apk --release
```

## How it works

When you enable notification access, the app can see media notifications from your music players. It picks up the song title and artist, then searches for lyrics across multiple sources (LRCLIB, Textyl, Musixmatch). Synced lyrics get priority when available.

The lyrics are cached locally so if you play the same song again, it loads instantly.

## Tech stuff

Built with Flutter/Dart. Uses Riverpod for state management. The notification listener is written in Kotlin on the Android side to interact with `MediaSessionManager`.

Project structure follows clean architecture - data layer handles API calls and caching, domain layer has the business logic, presentation layer is all the UI.

## Privacy

- No accounts or tracking
- No data sent to third party analytics
- Only permission needed is notification access (to detect songs)
- Everything is stored locally on your device

## Known issues

- Some music apps don't expose song metadata properly - lyrics won't work for those
- Synced scrolling requires the music to be playing (obviously)
- First install might need a phone restart if notification access doesn't kick in immediately

## Contributing

Found a bug? Want to add a feature? PRs welcome.

## License

MIT

---

Built by Avaneesh
