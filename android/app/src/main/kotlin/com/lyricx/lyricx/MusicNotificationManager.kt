package com.lyricx.lyricx

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Unified notification manager for music detection notifications across the app.
 * Keeps the notification alive whether MediaNotificationListener or MainActivity detects playback.
 */
object MusicNotificationManager {

    private const val TAG = "MusicNotifManager"
    const val NOTIFICATION_ID = 2002
    const val CHANNEL_ID = "flashlyrics_now_playing"

    private var lastNotifiedSongKey: String? = null
    private var lastNotifiedPlaying: Boolean? = null

    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Now Playing",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Shows when music is playing — tap to view lyrics or float"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            nm?.createNotificationChannel(channel)
        }
    }

    fun hasNotificationPermission(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= 33) {
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    fun showMusicNotification(
        context: Context,
        title: String,
        artist: String,
        source: String,
        isPlaying: Boolean,
        packageName: String
    ) {
        if (title.isBlank() || artist.isBlank()) {
            return
        }

        if (!hasNotificationPermission(context)) {
            Log.w(TAG, "Cannot show music notification: POST_NOTIFICATIONS not granted")
            return
        }

        createNotificationChannel(context)

        val currentKey = "$title|$artist|$source"
        // Avoid spamming identical notifications
        if (currentKey == lastNotifiedSongKey && isPlaying == lastNotifiedPlaying) {
            return
        }
        lastNotifiedSongKey = currentKey
        lastNotifiedPlaying = isPlaying

        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // Intent to open MainActivity
            val openAppIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("autoShowOverlay", false)
                putExtra("title", title)
                putExtra("artist", artist)
            }
            val openPending = PendingIntent.getActivity(
                context, 100, openAppIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Float action via FloatTrampolineActivity
            val floatIntent = Intent(context, FloatTrampolineActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("title", title)
                putExtra("artist", artist)
                putExtra("lyrics", OverlayLyricsCache.plain)
                putExtra("lrcLyrics", OverlayLyricsCache.lrc)
                putExtra("syncOffsetMs", OverlayLyricsCache.syncOffsetMs)
                putExtra("enableSeek", OverlayLyricsCache.seekEnabled)
            }
            val floatPending = PendingIntent.getActivity(
                context, 101, floatIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Dismiss action
            val dismissIntent = Intent(context, DismissMusicReceiver::class.java)
            val dismissPending = PendingIntent.getBroadcast(
                context, 102, dismissIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val statusText = if (isPlaying) {
                "$artist • $source — Tap for lyrics"
            } else {
                "$artist • $source (Paused)"
            }

            val bigTextContent = if (isPlaying) {
                "$artist • $source\nTap to open lyrics, or tap Float for floating window"
            } else {
                "$artist • $source (Paused)\nTap to open lyrics, or tap Float for floating window"
            }

            // Prefer app icon, fallback to media play icon
            val appIconRes = context.applicationInfo.icon.takeIf { it != 0 }
                ?: android.R.drawable.ic_media_play

            val notif = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(appIconRes)
                .setContentTitle(title)
                .setContentText(statusText)
                .setStyle(NotificationCompat.BigTextStyle().bigText(bigTextContent))
                .setOngoing(false)
                .setAutoCancel(false)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setContentIntent(openPending)
                .addAction(
                    NotificationCompat.Action(
                        android.R.drawable.ic_menu_view,
                        "Float",
                        floatPending
                    )
                )
                .addAction(
                    NotificationCompat.Action(
                        android.R.drawable.ic_menu_close_clear_cancel,
                        "Dismiss",
                        dismissPending
                    )
                )
                .build()

            nm.notify(NOTIFICATION_ID, notif)
            Log.d(TAG, "Music notification posted: $title by $artist (playing=$isPlaying)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show music notification", e)
        }
    }

    fun cancelMusicNotification(context: Context) {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(NOTIFICATION_ID)
            lastNotifiedSongKey = null
            lastNotifiedPlaying = null
            Log.d(TAG, "Music notification cancelled")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cancel music notification", e)
        }
    }

    /**
     * Ensure the MediaNotificationListener service is bound by Android OS.
     * Android often disconnects NotificationListenerService upon APK reinstall or update.
     */
    fun ensureListenerBound(context: Context) {
        try {
            val componentName = ComponentName(context, MediaNotificationListener::class.java)
            val flat = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
            val isGranted = flat != null && flat.contains(componentName.flattenToString())
            
            if (isGranted) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    NotificationListenerService.requestRebind(componentName)
                    Log.d(TAG, "Requested rebind for MediaNotificationListener")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "ensureListenerBound error: ${e.message}")
        }
    }
}
