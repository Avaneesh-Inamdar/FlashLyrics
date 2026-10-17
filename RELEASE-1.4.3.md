# FlashLyrics 1.4.3 (version code 15)

- The native notification listener tracks the active music player without depending on the Flutter screen. Reconnection and callback cleanup prevent stale registrations and paused players overriding active playback.
- Float resolves Android's current media session when tapped. Notification intents no longer carry an old lyric payload, and unrelated cached lyrics cannot replace the active song.
- The visible overlay can read matching saved lyrics and use a bounded, exact-match LRCLIB fallback when Flutter is closed. Failed lookups show an unavailable message; late results are discarded after a song change or service shutdown.
- The karaoke preference survives track changes and app restarts. Settings includes a Karaoke Mode switch.
- Per-song offsets preserve non-English names. Manual selections are saved with metadata, the Library refreshes after cache writes, and a damaged cache entry does not erase other saved songs.

Google Play upload artifact: `FlashLyrics-1.4.3-v15.aab` (local only).
GitHub release artifact: `FlashLyrics-1.4.3-v15.apk`.

Validation: 81 Flutter tests and 7 Robolectric Android regression tests passed. Tests cover playback changes without Flutter, notification listener reconnect/cleanup, stale Float payloads, exact offline/provider matching, Unicode offsets, saved karaoke preferences, cache writes and search latency. Flutter analysis reports no errors; existing warnings and style findings remain. Physical-device force-stop and vendor battery restrictions still require device verification. Android force-stop prevents background callbacks until the user opens the app again; this release does not bypass that OS behavior.
