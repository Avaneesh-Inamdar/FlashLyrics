# FlashLyrics 1.4.2 (version code 12)

- Word-by-word highlighting from LRCLIB Lyricsfile timestamps and enhanced LRC. No estimated word timings or extra lookup requests. Line-only and plain-text lyrics remain supported. Existing cached lyrics can be refreshed to request newer timing data.
- Compact song card, collapsible playback controls, and an earlier reading position on the home screen. Long lyric rows adapt to their text size.
- Settings checks update availability through Google Play, with a store link and a clear fallback when checking fails.
- One-time guidance explains how to expand the FlashLyrics notification and tap Float; the same help is available in Settings.
- Updated AndroidX Activity, retained edge-to-edge and safe insets, removed explicit system-bar color overrides. Native floating lyrics strip inline timing markers.

Validation: 56 Flutter tests passed, including lookup latency, ad-transition recovery, timing parsing/caching, pause/backward seek, update-check success/failure, first-use guidance, and narrow-screen layouts in both themes. Static analysis has no errors; existing warnings/info remain.

Physical-device music/ad transitions, Google Play update eligibility, and Play Console warning clearance require device/Console verification. The screenshot did not list the deprecated API call sites; framework or SDK compatibility paths may still be reported.

Version code 12 supersedes the previously uploaded version code 11.

Timing format references: https://lrclib.net/docs and https://github.com/tranxuanthang/lyricsfile/blob/main/SPECIFICATION.md
