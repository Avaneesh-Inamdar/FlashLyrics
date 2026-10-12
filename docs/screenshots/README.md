# README screenshots

These PNGs render the current `MainScreen` and its actual listening, library and settings widgets in both app themes, supplied through test providers. The listening screen features **On & On** by Cartoon, Jéja and Daniel Levi, with its official NCS artwork and a short lyric excerpt. Word timings are an illustrative capture fixture, not a claim about timing availability for that track. Library entries demonstrate cached-track metadata.

## Artwork credit

- Song: Cartoon, Jéja — On & On (feat. Daniel Levi) [NCS Release]. Music provided by NoCopyrightSounds.
- Official release and download/stream: https://ncs.io/onandon
- Official artwork source: https://ncsmusic.s3.eu-west-1.amazonaws.com/tracks/000/000/152/1000x0/1705340894_JZ2NifV4gB_2024---CARTOON-JEYJA---On--On-ft.-Daniel-Levi.jpg
- Other library tracks: Heroes Tonight — Janji feat. Johnning; Invincible — DEAF KEV.

Artwork is credited to its respective rights holders and is not relicensed by this repository. NCS’s music usage terms do not imply that all artwork is public domain.

Regenerate from the repository root:

```sh
flutter test test/readme_screenshots_test.dart --dart-define=CAPTURE_README=true
```

The capture uses a 390 × 844 logical-pixel viewport at 2× resolution with system-safe padding. It disables optional ads, acknowledges the first-use tip and supplies deterministic cached lyrics. Listening captures simulate active playback and verify the Live indicator and a decoded cover image before capturing. The gallery includes collapsed and expanded playback controls. Native notification and media APIs are mocked; these images do not demonstrate an Android overlay or device permission flow.

Captures are written directly to this directory. Review them before committing after changing the theme, navigation, typography or listening layout.
