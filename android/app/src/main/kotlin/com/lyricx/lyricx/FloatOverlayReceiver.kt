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
        val overlayIntent = NativeOverlayIntent.forCurrentSong(context) ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(overlayIntent)
            } else {
                context.startService(overlayIntent)
            }
            Log.d(TAG, "Overlay service started for current playback")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start overlay service", e)
        }
    }
}
