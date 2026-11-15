# FlashLyrics 1.4.5

- **Overlay Song Title** (Settings): hide the title and artist at the top of the floating window to give the lyrics more room. With the title hidden, the close button moves to the bottom row, and you can move the window by dragging the bottom row or the lyrics.
- **TV Mode** (Settings): the floating window shows only the lyrics, with larger text, centred at the bottom of the screen. It's made for Android TV and reading from the couch, and the switches work with a TV remote. To close the window, use **Hide** on the Listening screen or in the notification. If tap-to-seek is off, you can drag the lyrics to move the window.
- Both options are off by default, so the floating window looks the same as before until you change them.

Download: `FlashLyrics-1.4.5.apk`.

Validation: 122 Flutter tests and 12 Robolectric Android tests passed, including new checks for both window layouts, their drag and close behaviour, TV-mode text size and bottom-centre placement, and settings saved by 1.4.4. Tested on an Android 15 phone emulator and an Android 16 Google TV emulator at 1080p. Testing included remote (D-pad) navigation of the new switches, and checking that the TV window stays centred as the lyric lines change. Flutter analysis reports no errors; existing warnings and style findings remain. The release manifest is the same as 1.4.4 apart from the version.
