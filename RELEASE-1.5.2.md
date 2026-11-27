# FlashLyrics 1.5.2

- **App Filter (Blacklist / Whitelist):** added per-app media detection filtering in Settings > General > App Filter (resolving [#7](https://github.com/Avaneesh-Inamdar/FlashLyrics/issues/7)).
  - **All:** detects all supported music & media apps (default).
  - **Blacklist:** ignore specific apps (such as video players or TV remotes like Yatse) so they never trigger lyric lookups or Now Playing notifications.
  - **Whitelist:** only detect music from the apps you explicitly allow.
  - **Smart discovery:** recently detected media-session apps appear at the top with a `Detected` badge, and you can also add any package name manually.

Download: `FlashLyrics-1.5.2.apk` (version 1.5.2, build 24).
Play Store bundle: `FlashLyrics-1.5.2-v24.aab`.

Validation: 206 Flutter tests passed (`flutter test`) and signed release APK & AAB built with R8.
