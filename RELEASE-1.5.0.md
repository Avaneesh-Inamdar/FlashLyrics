# FlashLyrics 1.5.0

- **Fixed:** some devices kept showing Google test ads. When the real ad could not load, the app fell back to a test ad. Release builds now only ever request the real ad units; if no ad is available, nothing is shown and the app tries again later. The old "use test ads" setting is gone.
- **Tablets:** the app now uses the whole screen. Tablets get a navigation rail on the side, can rotate to landscape, and the Listening screen shows the song and controls beside the lyrics. Lists and settings are centred at a readable width.
- **Android TV:** FlashLyrics now appears in the TV launcher with its own banner and works with a remote. The navigation rail is on the left, the D-pad moves between items and a clear outline shows what is selected. Text is a little larger for the couch. Ads and the support options are not shown on TV.
- **Update notice:** when a newer version is on Google Play, the app now tells you when you open it: "A new version of FlashLyrics is available. Please download it from the Play Store."
- Settings screens that Android TV may not have (notification access, display over other apps) no longer crash the app; it opens the app's settings instead.
- The Listening screen's setup cards scroll on short screens instead of overflowing.

Download: `FlashLyrics-1.5.0.apk` (version 1.5.0, build 21).

Validation: 182 Flutter tests passed. Tested a debug build on an Android 15 tablet emulator (2560x1600) and an Android TV emulator (1920x1080, D-pad only), and smoke-tested the signed release build on both. The release APK is signed with the same key as earlier releases.
