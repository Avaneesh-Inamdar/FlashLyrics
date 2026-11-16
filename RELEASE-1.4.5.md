# FlashLyrics 1.4.5

- **Overlay Song Title** (Settings): hide the title and artist at the top of the floating window to give the lyrics more room. With the title hidden, the close button moves to the bottom row, and you can move the window by dragging the bottom row or the lyrics.
- **TV Mode** (Settings): the floating window shows only the lyrics, with larger text, centred at the bottom of the screen. It's made for Android TV and reading from the couch, and the switches work with a TV remote. To close the window, use **Hide** on the Listening screen or in the notification. If tap-to-seek is off, you can drag the lyrics to move the window.
- Both options are off by default, so the floating window looks the same as before until you change them.

## Update (build 18)

- **Support development** is now the first section in Settings. It has **Watch an Ad to Support** (an optional short video ad), the ads on/off switch and Buy Me a Coffee.
- A short reminder that FlashLyrics is free can appear when the app opens, at most once a day and never on the first day. **OK** opens Settings and highlights the ads switch (or Watch an Ad when ads are already on). **Remind me later** waits a day, and **No thanks** stops the reminder.
- After you've listened to 3 songs, FlashLyrics asks once for a Google Play rating, with **Rate on Google Play**, **Remind me later** (asks again after 4 more songs, and no sooner than tomorrow) and **Don't remind me again**. The rating and support reminders never appear in the same session.
- **Fixed:** opening an ad no longer adds a second FlashLyrics card to the recent apps screen.
- **Fixed:** library thumbnails were blank for songs from Spotify, YouTube Music and other players that share artwork as an image. These now show the saved artwork, and if it was cleared, a matching cover is looked up online.

## Update (build 19)

- **Full-screen lyrics:** tap the full-screen button at the top of the Listening screen. Lyrics fill the screen and the status and navigation bars are hidden. The screen stays on while it's open, and it follows song changes.
  - **A− / A+** change the text size, which is remembered.
  - Tap a line to jump to it, earlier or later in the song.
  - **Long-press** a line to select it, tap more lines to extend the selection, then **Share** them as an image.
  - **Back** ends a selection first, then leaves full screen.
  - When ads are on, a banner shows at the bottom.

Download: `FlashLyrics-1.4.5.apk` (version 1.4.5, build 19).

Validation (build 18): 143 Flutter tests and 12 Robolectric Android tests passed. Tested on an Android 15 emulator:
- An ad screen opened in a new task showed two FlashLyrics cards in Recents before the fix and one after. Back returns to the app without restarting it.
- The rewarded test ad played, granted the reward and showed the thank-you message. Clicking the test ad did not create a second card.
- The daily reminder and its OK highlight worked, as did the rating prompt after the 3rd song and its link to the Play Store page.
- Library artwork showed from player images, and from the online lookup after the cached image was deleted. The floating window still opens from the notification.

The release build was smoke-tested in airplane mode. It is signed with the same key as earlier releases. The manifest differs from build 17 only in the version code and the launch activity's task affinity.

Validation (build 19): 159 Flutter tests and 12 Robolectric Android tests passed. Tested on an Android 15 emulator in light and dark themes:
- Opening and closing full screen hides and restores the system bars. The banner showed in full screen, and the Listening screen was unchanged after closing.
- Tapping an earlier line and a later line jumped playback back and forward.
- Long-press selected the pressed line, and extending to five lines and sharing opened the share sheet with the lyrics image. Sharing from the Listening screen still works.

The release build was smoke-tested in airplane mode, using imported lyrics. It is signed with the same key, and the manifest differs from build 18 only in the version code.
