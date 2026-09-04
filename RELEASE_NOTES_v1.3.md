## ⚠️ IMPORTANT: Uninstall Old Version (v1.2.0 or Earlier) First!

**FlashLyrics is transitioning to the Google Play Store!**

This release uses the official Google Play Store release signing key.
Because of Android's security signature verification:
1. **Uninstall your existing FlashLyrics app (v1.2.0 or earlier) first.**
2. **Download and install `FlashLyrics-v1.3.0.apk` below.**

> **Note**: If you attempt to install v1.3.0 directly over v1.2.0 without uninstalling first, Android will show an *"App not installed / Signature mismatch"* error due to the new signing key.

---

# 🎉 What's New in v1.3.0 (v1.30)

### 🪟 Floating Lyrics Overlay Window
- Real-time lyrics floating widget that stays on top of Spotify, YouTube Music, Apple Music, and any music app!
- Supports auto-scroll, smooth tap-to-seek, and fluid multidirectional resizing (both width and height).
- Instant skeleton loading animation when tracks change so you never see stale lyrics.

### 🔔 Now Playing Notification with 1-Tap "Float" Action
- Persistent system notification displaying current track title, artist, and playback status (including `(Paused)` state).
- Tapping the **"Float"** button in the notification immediately brings up the floating lyrics overlay without opening the full application window.
- Direct dismiss option included.

### ⚡ Butter-Smooth Zero-Jank Performance
- Eliminated main-thread rebuilds and image cache thrashing.
- Tuned platform channel IPC frequency for buttery-smooth 120Hz scrolling and instant app switching without frame drops.

### 📤 Smart Share Navigation
- Tapping the Share button now automatically selects and scrolls straight to the currently playing lyric line.
- Centered lyric layout with album cover art and song credits included in the generated image.
- Widget-scoped selection state to ensure returning to the app never gets stuck in share mode.

### ☕ Support & Buy Me a Coffee
- Added official Buy Me a Coffee support tile in Settings and on GitHub for users who wish to support project development.

### 📢 Optional AdMob Integration
- Added non-intrusive banner ads to support free development, with a simple toggle in Settings to turn ads off anytime.

### 🏬 Google Play Store Preparation
- Configured production release keystore and updated permissions for upcoming Google Play Store distribution.

---

## 📥 Downloads
- **Primary APK**: `FlashLyrics-v1.3.0.apk` (or `app-release.apk`)
- **Android Compatibility**: Android 8.0 (API 26) through Android 16 (API 36)
