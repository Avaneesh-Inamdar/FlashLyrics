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

Download: `FlashLyrics-1.4.5.apk` (version 1.4.5, build 18).

Validation: 143 Flutter tests and 12 Robolectric Android tests passed. Tested on an Android 15 emulator:
- An ad screen opened in a new task showed two FlashLyrics cards in Recents before the fix and one after. Back returns to the app without restarting it.
- The rewarded test ad played, granted the reward and showed the thank-you message. Clicking the test ad did not create a second card.
- The daily reminder and its OK highlight worked, as did the rating prompt after the 3rd song and its link to the Play Store page.
- Library artwork showed from player images, and from the online lookup after the cached image was deleted. The floating window still opens from the notification.

The release build was smoke-tested in airplane mode. It is signed with the same key as earlier releases. The manifest differs from build 17 only in the version code and the launch activity's task affinity.
