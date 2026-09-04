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

        val title = intent.getStringExtra("title") ?: OverlayLyricsCache.title
        val artist = intent.getStringExtra("artist") ?: OverlayLyricsCache.artist
        val lrc = intent.getStringExtra("lrcLyrics") ?: OverlayLyricsCache.lrc
        val plain = intent.getStringExtra("lyrics") ?: OverlayLyricsCache.plain
        val offset = intent.getIntExtra("syncOffsetMs", OverlayLyricsCache.syncOffsetMs)
        val seek = intent.getBooleanExtra("enableSeek", OverlayLyricsCache.seekEnabled)

        val overlayIntent = Intent(this, LyricsOverlayService::class.java).apply {
            action = LyricsOverlayService.ACTION_SHOW
            putExtra("title", title)
            putExtra("artist", artist)
            putExtra("lrcLyrics", lrc)
            putExtra("lyrics", plain)
            putExtra("currentLine", "")
            putExtra("syncOffsetMs", offset)
            putExtra("enableSeek", seek)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(overlayIntent)
            } else {
                startService(overlayIntent)
            }
            Log.d(TAG, "Overlay service started for $title by $artist")
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
