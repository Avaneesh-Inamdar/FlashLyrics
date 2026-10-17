package com.lyricx.lyricx

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log

/**
 * Transparent trampoline activity that collapses the notification shade / status bar
 * when "Float" is tapped in the music notification, starts LyricsOverlayService,
 * and immediately finishes without showing any UI or opening the main app.
 */
class FloatTrampolineActivity : Activity() {

    companion object {
        private const val TAG = "FloatTrampoline"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Check overlay permission
        val hasOverlayPerm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }

        if (!hasOverlayPerm) {
            try {
                val permIntent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                ).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(permIntent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to open overlay permission settings", e)
            }
            finish()
            return
        }

        val overlayIntent = NativeOverlayIntent.forCurrentSong(this)
        if (overlayIntent == null) {
            MusicNotificationManager.cancelMusicNotification(this)
            android.widget.Toast.makeText(this, "No active music found. Start playback and try again.", android.widget.Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(overlayIntent)
            } else {
                startService(overlayIntent)
            }
            Log.d(TAG, "Overlay service started for current playback")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start overlay service", e)
        }

        finish()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            overrideActivityTransition(OVERRIDE_TRANSITION_OPEN, 0, 0)
            overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0)
        } else {
            @Suppress("DEPRECATION")
            overridePendingTransition(0, 0)
        }
    }
}
