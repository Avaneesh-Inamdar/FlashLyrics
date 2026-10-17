package com.lyricx.lyricx

import android.content.Context
import android.content.Intent

object NativeOverlayIntent {
    fun forCurrentSong(context: Context): Intent? {
        MusicNotificationManager.ensureListenerBound(context)
        val song = NativePlayback.current(context) ?: return null
        val cached = OverlayLyricsCache.forSong(song)
        val options = NativeLyricsLoader.options(context, song)
        return Intent(context, LyricsOverlayService::class.java).apply {
            action = LyricsOverlayService.ACTION_SHOW
            putExtra("title", song.title)
            putExtra("artist", song.artist)
            putExtra("lyrics", cached?.plain ?: "")
            putExtra("lrcLyrics", cached?.lrc ?: "")
            putExtra("syncOffsetMs", cached?.offset ?: options.first)
            putExtra("enableSeek", options.second)
        }
    }
}
