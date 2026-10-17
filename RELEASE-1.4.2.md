# FlashLyrics 1.4.2 (version code 14)

- Karaoke is a saved preference across tracks and app restarts, with a matching Settings switch. Turning it off disables estimated karaoke on subsequent tracks.
- Per-song timing adjustments retain non-English names and use the displayed lyrics' metadata. Word fill and line selection respect positive/negative offsets during playback and while paused.
- Manual selections are cached with their metadata. Library refreshes after successful cache writes. Serialized mutations and isolated decoding preserve other saved songs when a cache entry is damaged.

- Smooth per-word fill, subtle lift and glow from LRCLIB Lyricsfile timestamps and enhanced LRC. Frame updates repaint only the active lyric. Pausing, seeking, reduced motion, wrapping and right-to-left layout remain supported.
- Lyrics appear immediately while an optional, bounded LRCLIB lookup searches for genuine word timings in the background. Matching upgrades are cached; late responses cannot replace a new song or manual selection.
- Line-only tracks have an optional Karaoke button, explicitly labelled as estimated timing. Estimates are visual only and are never saved as provider timings. Plain lyrics remain readable.
- Compact song card, collapsible playback controls without divider lines, and an earlier reading position on the home screen. Long lyric rows adapt to their text size.
- Search returns available matches after a short collection window instead of waiting for stalled providers.
- Settings checks update availability through Google Play, with a store link and a clear fallback when checking fails.
- One-time guidance explains how to expand the FlashLyrics notification and tap Float; the same help is available in Settings.
- Updated AndroidX Activity, retained edge-to-edge and safe insets, removed explicit system-bar color overrides. Native floating lyrics strip inline timing markers.

Validation: 81 Flutter tests passed, including saved karaoke preference across track changes/restart, immediate word/line offsets while paused and playing, Unicode offset persistence, selected-song caching and live Library refresh, damaged-entry isolation, concurrent cache writes, synced-only offline results, and lookup/search latency with stalled providers. Existing recovery, timing, layout, update, guidance and screenshot checks also passed. Static analysis has no errors; warnings/info remain.

Physical-device music/ad transitions, Google Play update eligibility, and Play Console warning clearance require device/Console verification. The screenshot did not list the deprecated API call sites; framework or SDK compatibility paths may still be reported.

Version code 14 supersedes version code 13.

Timing format references: https://lrclib.net/docs and https://github.com/tranxuanthang/lyricsfile/blob/main/SPECIFICATION.md
