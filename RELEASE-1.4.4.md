# FlashLyrics 1.4.4

- Import your own lyrics from a `.lrc` or `.txt` file, or paste text. Choose the song and artist, preview the lyrics, and confirm before replacing an existing entry. Imports stay on your device and are available offline.
- Line timestamps and enhanced LRC word timestamps work with the existing synced and karaoke displays. Invalid or mixed timing is explained before saving. Plain lyrics are also supported.
- Automatic lookups and late provider responses preserve your imported lyrics. Delete the entry from Library to return to online lyrics.
- Genius cover artwork is retained when lyrics are saved, reopened, selected manually or upgraded with timing data. Library details and shared images use the selected song's metadata.
- Shared lyric images strip line timestamps, word timestamps and LRC metadata before drawing.
- An occasional Google Play review prompt offers **Leave a review now**, **Ask me later**, and **Never**. Reminders wait until the app has been used, respect a two-week snooze, and remember opt-out. The review button opens Google Play with a browser fallback.

Download: `FlashLyrics-1.4.4.apk`.

Validation: 116 Flutter tests and 7 Robolectric Android regression tests passed. Checks include timestamp validation, Unicode identity, UTF-8/UTF-16 files, file cancellation and read errors, replacement confirmation, failed saves, offline persistence, concurrent provider/import writes, Genius artwork retention, review reminder choices and search latency. PNG exports from timestamped imports match clean-lyrics exports. Flutter analysis reports no errors; existing warnings and style findings remain. Physical Android file-provider behavior and Google Play review availability need device verification; no phone was connected during automated checks.
