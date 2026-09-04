package com.lyricx.lyricx

/**
 * Simple in-memory cache for latest lyrics so native notification can show floating window
 * without needing Flutter to be in foreground. Updated from Flutter via MethodChannel.
 */
object OverlayLyricsCache {
    @Volatile var title: String = ""
    @Volatile var artist: String = ""
    @Volatile var lrc: String = ""
    @Volatile var plain: String = ""
    @Volatile var syncOffsetMs: Int = 0
    @Volatile var seekEnabled: Boolean = false

    fun update(title: String, artist: String, lrcLyrics: String?, plainLyrics: String?, offset: Int, enableSeek: Boolean = seekEnabled) {
        this.title = title
        this.artist = artist
        this.lrc = lrcLyrics ?: ""
        this.plain = plainLyrics ?: ""
        this.syncOffsetMs = offset
        this.seekEnabled = enableSeek
    }

    fun matches(songTitle: String, songArtist: String): Boolean {
        return title.equals(songTitle, ignoreCase = true) && artist.equals(songArtist, ignoreCase = true)
    }

    fun hasLyrics(): Boolean = lrc.isNotEmpty() || plain.isNotEmpty()
}
