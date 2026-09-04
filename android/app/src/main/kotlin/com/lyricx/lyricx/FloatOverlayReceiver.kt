package com.lyricx.lyricx

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Handles the "Float" action in the music notification.
 * Collapses the status bar / notification panel, then starts LyricsOverlayService.
 */
class FloatOverlayReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "FloatOverlayReceiver"
        const val ACTION_FLOAT = "com.lyricx.lyricx.ACTION_FLOAT_OVERLAY"
    }

    @Suppress("DEPRECATION")
    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Received float action — collapsing panel and showing overlay")

        // 1. Close the notification / status bar panel.
        //    On API ≤ 30 we can send the system broadcast.  On API 31+ this broadcast
        //    is restricted but the system automatically collapses it when a
        //    foreground-service start is triggered from a receiver.
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                @Suppress("DEPRECATION")
                context.sendBroadcast(Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS))
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not close system dialogs: ${e.message}")
        }

        // 2. Extract all overlay extras forwarded by MediaNotificationListener
        val title   = intent.getStringExtra("title")   ?: OverlayLyricsCache.title
        val artist  = intent.getStringExtra("artist")  ?: OverlayLyricsCache.artist
        val lrc     = intent.getStringExtra("lrcLyrics") ?: OverlayLyricsCache.lrc
        val plain   = intent.getStringExtra("lyrics")  ?: OverlayLyricsCache.plain
        val offset  = intent.getIntExtra("syncOffsetMs", OverlayLyricsCache.syncOffsetMs)
        val seek    = intent.getBooleanExtra("enableSeek", OverlayLyricsCache.seekEnabled)

        // 3. Start the overlay service
        val overlayIntent = Intent(context, LyricsOverlayService::class.java).apply {
            action = LyricsOverlayService.ACTION_SHOW
            putExtra("title",       title)
            putExtra("artist",      artist)
            putExtra("lrcLyrics",   lrc)
            putExtra("lyrics",      plain)
            putExtra("currentLine", "")
            putExtra("syncOffsetMs", offset)
            putExtra("enableSeek",  seek)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(overlayIntent)
            } else {
                context.startService(overlayIntent)
            }
            Log.d(TAG, "Overlay service started for $title by $artist")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start overlay service", e)
        }
    }
}
