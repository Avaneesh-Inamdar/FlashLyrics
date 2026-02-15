package com.lyricx.lyricx

import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Main Activity with Flutter method channel integration for media detection.
 */
class MainActivity : FlutterActivity() {
    
    companion object {
        private const val METHOD_CHANNEL = "com.lyricx/media"
        private const val EVENT_CHANNEL = "com.lyricx/media_events"
    }
    
    private var eventSink: EventChannel.EventSink? = null
    
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Method channel for calling native methods
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkNotificationAccess" -> {
                    result.success(isNotificationAccessEnabled())
                }
                "requestNotificationAccess" -> {
                    openNotificationAccessSettings()
                    result.success(null)
                }
                "isServiceRunning" -> {
                    result.success(MediaNotificationListener.isRunning)
                }
                "checkOverlayPermission" -> {
                    result.success(checkOverlayPermission())
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(null)
                }
                "getCurrentPlayingSong" -> {
                    result.success(MediaNotificationListener.getCurrentSong())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Event channel for streaming media updates to Flutter
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    setupMediaListener()
                }
                
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    MediaNotificationListener.mediaUpdateListener = null
                }
            }
        )
    }
    
    private fun setupMediaListener() {
        MediaNotificationListener.mediaUpdateListener = object : MediaNotificationListener.MediaUpdateListener {
            override fun onMediaUpdate(
                title: String?,
                artist: String?,
                album: String?,
                artworkUrl: String?,
                duration: Long,
                source: String?,
                isPlaying: Boolean
            ) {
                runOnUiThread {
                    eventSink?.success(mapOf(
                        "type" to "media_update",
                        "title" to (title ?: ""),
                        "artist" to (artist ?: ""),
                        "album" to (album ?: ""),
                        "artworkUrl" to (artworkUrl ?: ""),
                        "duration" to duration,
                        "source" to (source ?: "Unknown"),
                        "isPlaying" to isPlaying
                    ))
                }
            }
            
            override fun onPlaybackStopped() {
                runOnUiThread {
                    eventSink?.success(mapOf(
                        "type" to "playback_stopped"
                    ))
                }
            }
        }
        // Force a session check when Flutter starts listening
        MediaNotificationListener.refreshActiveSessions()
    }
    
    private fun isNotificationAccessEnabled(): Boolean {
        val componentName = ComponentName(this, MediaNotificationListener::class.java)
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat != null && flat.contains(componentName.flattenToString())
    }
    
    private fun openNotificationAccessSettings() {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        startActivity(intent)
    }
    
    private fun checkOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }
    
    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                android.net.Uri.parse("package:$packageName")
            )
            startActivity(intent)
        }
    }
}
