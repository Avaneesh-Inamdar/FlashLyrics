package com.lyricx.lyricx

/**
 * Simple in-memory cache for latest lyrics so native notification can show floating window
 * without needing Flutter to be in foreground. Updated from Flutter via MethodChannel.
 */
object OverlayLyricsCache {
    data class Entry(val title: String = "", val artist: String = "",
        val lrc: String = "", val plain: String = "", val offset: Int = 0)
    @Volatile private var entry = Entry()
    val title get() = entry.title
    val artist get() = entry.artist
    val lrc get() = entry.lrc
    val plain get() = entry.plain
    val syncOffsetMs get() = entry.offset
    @Volatile var seekEnabled: Boolean = false

    fun snapshot(): Entry = entry

    fun forSong(song: NativeSong): Entry? = entry.takeIf { song.matches(it.title, it.artist) }

    fun update(title: String, artist: String, lrcLyrics: String?, plainLyrics: String?, offset: Int, enableSeek: Boolean = seekEnabled) {
        entry = Entry(title, artist, lrcLyrics ?: "", plainLyrics ?: "", offset)
        this.seekEnabled = enableSeek
    }

    fun matches(songTitle: String, songArtist: String): Boolean {
        return title.equals(songTitle, ignoreCase = true) && artist.equals(songArtist, ignoreCase = true)
    }

    fun hasLyrics(): Boolean = lrc.isNotEmpty() || plain.isNotEmpty()
}
