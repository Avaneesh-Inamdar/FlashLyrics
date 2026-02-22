package com.lyricx.lyricx

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Main Activity with Flutter method channel integration for media detection.
 */
class MainActivity : FlutterActivity() {
    
    companion object {
        private const val TAG = "MainActivity"
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
                    // Consider service "running" if we can query media sessions directly
                    val nativeRunning = MediaNotificationListener.isRunning
                    val canQuery = isNotificationAccessEnabled()
                    Log.d(TAG, "isServiceRunning: native=$nativeRunning, canQuery=$canQuery")
                    result.success(nativeRunning || canQuery)
                }
                "checkOverlayPermission" -> {
                    result.success(checkOverlayPermission())
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(null)
                }
                "getCurrentPlayingSong" -> {
                    // ALWAYS query MediaSessionManager directly first
                    // NLS static data gets stale when MIUI kills the service
                    var songData: Map<String, Any?>? = null
                    
                    if (isNotificationAccessEnabled()) {
                        songData = queryMediaSessionsDirect()
                    }
                    
                    // Fallback to NLS static data only if direct query fails
                    if (songData == null) {
                        songData = MediaNotificationListener.getCurrentSong()
                    }
                    
                    if (songData != null) {
                        Log.d(TAG, "getCurrentPlayingSong: ${songData["title"]} by ${songData["artist"]} playing=${songData["isPlaying"]}")
                    } else {
                        Log.d(TAG, "getCurrentPlayingSong: null")
                    }
                    result.success(songData)
                }
                "seekTo" -> {
                    val position = call.argument<Int>("position")?.toLong() ?: 0L
                    val success = seekToPosition(position)
                    result.success(success)
                }
                "setPlaying" -> {
                    val playing = call.argument<Boolean>("playing") ?: false
                    val success = setPlaybackState(playing)
                    result.success(success)
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
                isPlaying: Boolean,
                position: Long
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
                        "isPlaying" to isPlaying,
                        "position" to position
                    ))
                }
            }
            
            override fun onPositionUpdate(position: Long, duration: Long, isPlaying: Boolean) {
                runOnUiThread {
                    eventSink?.success(mapOf(
                        "type" to "position_update",
                        "position" to position,
                        "duration" to duration,
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
    
    /**
     * Directly query MediaSessionManager for active media sessions.
     * This works even when MIUI/Xiaomi has killed the NotificationListenerService
     * because the notification listener PERMISSION is still granted.
     */
    private fun queryMediaSessionsDirect(): Map<String, Any?>? {
        return try {
            val msm = getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
                ?: return null
            
            val componentName = ComponentName(this, MediaNotificationListener::class.java)
            val controllers = msm.getActiveSessions(componentName)
            
            Log.d(TAG, "Direct query found ${controllers.size} active sessions")
            
            // Find first playing session, or first session with metadata
            var bestController: android.media.session.MediaController? = null
            var bestIsPlaying = false
            
            for (controller in controllers) {
                val pkg = controller.packageName
                val state = controller.playbackState?.state
                val metadata = controller.metadata
                val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE)
                val artist = metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST)
                    ?: metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
                
                Log.d(TAG, "Session: pkg=$pkg, state=$state, title=$title, artist=$artist")
                
                if (title.isNullOrEmpty() || artist.isNullOrEmpty()) continue
                
                val isPlaying = state == PlaybackState.STATE_PLAYING
                
                // Prefer playing sessions over paused ones
                if (isPlaying && !bestIsPlaying) {
                    bestController = controller
                    bestIsPlaying = true
                } else if (bestController == null) {
                    bestController = controller
                    bestIsPlaying = isPlaying
                }
            }
            
            if (bestController == null) return null
            
            val metadata = bestController.metadata ?: return null
            val title = metadata.getString(MediaMetadata.METADATA_KEY_TITLE) ?: return null
            val artist = metadata.getString(MediaMetadata.METADATA_KEY_ARTIST)
                ?: metadata.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST) ?: return null
            val album = metadata.getString(MediaMetadata.METADATA_KEY_ALBUM)
            val duration = metadata.getLong(MediaMetadata.METADATA_KEY_DURATION)
            val position = bestController.playbackState?.position ?: 0L
            val isPlaying = bestController.playbackState?.state == PlaybackState.STATE_PLAYING
            
            // Extract album art - try URI first, then bitmap
            var artworkUrl: String? = metadata.getString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI)
                ?: metadata.getString(MediaMetadata.METADATA_KEY_ART_URI)
            
            // If URI is a content:// URI, try to cache it as a file
            if (!artworkUrl.isNullOrEmpty() && artworkUrl.startsWith("content://")) {
                artworkUrl = cacheContentUri(artworkUrl, title, artist)
            }
            
            // If no URI, try to get bitmap and cache it
            if (artworkUrl.isNullOrEmpty()) {
                val bitmap = metadata.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                    ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_ART)
                if (bitmap != null) {
                    artworkUrl = cacheArtworkBitmap(bitmap, title, artist)
                }
            }
            
            // Also update the NLS static data so future polls are fast
            MediaNotificationListener.currentTitle = title
            MediaNotificationListener.currentArtist = artist
            MediaNotificationListener.currentAlbum = album
            MediaNotificationListener.currentArtworkUrl = artworkUrl
            MediaNotificationListener.currentDuration = duration
            MediaNotificationListener.currentIsPlaying = isPlaying
            MediaNotificationListener.currentPosition = position
            
            val source = getSourceNameForPackage(bestController.packageName)
            MediaNotificationListener.currentSource = source
            
            Log.d(TAG, "Direct query found: $title by $artist ($source), art=$artworkUrl")
            
            mapOf(
                "title" to title,
                "artist" to artist,
                "album" to album,
                "artworkUrl" to artworkUrl,
                "duration" to duration,
                "source" to source,
                "isPlaying" to isPlaying,
                "position" to position
            )
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException in direct query - need notification access", e)
            null
        } catch (e: Exception) {
            Log.e(TAG, "Error in direct MediaSession query", e)
            null
        }
    }
    
    private fun cacheArtworkBitmap(bitmap: Bitmap, title: String, artist: String): String? {
        return try {
            val safeName = ("${title}_${artist}")
                .lowercase()
                .replace(Regex("[^a-z0-9_]+"), "_")
                .trim('_')
            val file = File(cacheDir, "art_direct_$safeName.png")
            // Only write if file doesn't exist or is old (avoid re-writing same art)
            if (!file.exists() || file.length() == 0L) {
                FileOutputStream(file).use { out ->
                    bitmap.compress(Bitmap.CompressFormat.PNG, 90, out)
                }
            }
            file.toURI().toString()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cache album art bitmap", e)
            null
        }
    }
    
    private fun cacheContentUri(uriString: String, title: String, artist: String): String? {
        return try {
            val safeName = ("${title}_${artist}")
                .lowercase()
                .replace(Regex("[^a-z0-9_]+"), "_")
                .trim('_')
            val uri = Uri.parse(uriString)
            val input = contentResolver.openInputStream(uri) ?: return null
            val file = File(cacheDir, "art_direct_${safeName}_uri.png")
            FileOutputStream(file).use { out ->
                input.copyTo(out)
            }
            input.close()
            file.toURI().toString()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cache content URI art", e)
            null
        }
    }
    
    private fun getSourceNameForPackage(packageName: String): String {
        return when (packageName) {
            // Major streaming
            "com.spotify.music" -> "Spotify"
            "com.google.android.apps.youtube.music", "app.revanced.android.youtube.music" -> "YouTube Music"
            "com.google.android.youtube" -> "YouTube"
            "com.apple.android.music" -> "Apple Music"
            "com.amazon.mp3" -> "Amazon Music"
            "com.soundcloud.android" -> "SoundCloud"
            "deezer.android.app" -> "Deezer"
            "com.pandora.android" -> "Pandora"
            "com.aspiro.tidal", "com.tidal.music" -> "Tidal"
            
            // Regional
            "com.jio.media.jiobeats" -> "JioSaavn"
            "com.gaana" -> "Gaana"
            "com.bsbportal.music" -> "Wynk Music"
            "com.hungama.myplay.activity" -> "Hungama"
            "com.qobuz.music" -> "Qobuz"
            "com.resso.app", "com.resso.music" -> "Resso"
            "com.anghami" -> "Anghami"
            "com.boomplay.music" -> "Boomplay"
            "com.yandex.music" -> "Yandex Music"
            "com.tencent.qqmusic" -> "QQ Music"
            "com.netease.cloudmusic" -> "NetEase Music"
            "com.kugou.android" -> "KuGou"
            "com.kuwo.player" -> "Kuwo"
            "jp.linecorp.linemusic" -> "LINE Music"
            "com.naver.vibe" -> "Vibe"
            "com.iloen.melon" -> "Melon"
            
            // Device players
            "com.sec.android.app.music", "com.samsung.android.app.music" -> "Samsung Music"
            "com.google.android.music" -> "Google Play Music"
            "com.android.music" -> "Music"
            "com.miui.player" -> "Mi Music"
            "com.oppo.music" -> "OPPO Music"
            "com.oneplus.music" -> "OnePlus Music"
            "com.huawei.music" -> "Huawei Music"
            "com.transsion.music" -> "Boomplay"
            "com.realme.music" -> "Realme Music"
            "com.vivo.music" -> "Vivo Music"
            
            // Third-party players
            "org.videolan.vlc" -> "VLC"
            "com.maxmpz.audioplayer" -> "Poweramp"
            "in.krosbits.musicolet" -> "Musicolet"
            "com.jrtstudio.music" -> "Rocket Player"
            "com.doubletwist.androidplayer" -> "doubleTwist"
            "com.neutroncode.mp" -> "Neutron"
            "com.bandcamp.android" -> "Bandcamp"
            "com.audible.application" -> "Audible"
            "com.foobar2000.foobar2000" -> "foobar2000"
            "com.google.android.apps.podcasts" -> "Google Podcasts"
            "com.spotify.lite" -> "Spotify Lite"
            "com.clearchannel.iheartradio.controller" -> "iHeartRadio"
            "tunein.player" -> "TuneIn"
            "com.audiomack" -> "Audiomack"
            "com.mixcloud.player" -> "Mixcloud"
            "fm.last.android" -> "Last.fm"
            "com.pocketcasts.android" -> "Pocket Casts"
            "com.shazam.android" -> "Shazam"
            "com.aspiro.tidal.lite" -> "Tidal"
            "com.naveed.ytmp3" -> "YTMP3"
            "com.flyingdog" -> "Nyx Music"
            "com.nox.evermusic" -> "Evermusic"
            "code.name.monkey.retromusic" -> "Retro Music"
            "com.tozelabs.musicplayer" -> "BlackPlayer"
            "com.tozelabs.musicplayerf" -> "BlackPlayer EX"
            "com.ympx.music" -> "Pi Music"
            "player.flavor.flavor" -> "Flavor Music"
            "com.joythis.joymusic" -> "Joy Music"
            
            else -> {
                // Try to derive a friendly name from the package
                when {
                    packageName.contains("music", ignoreCase = true) -> {
                        val parts = packageName.split(".")
                        val appPart = parts.lastOrNull { it != "music" && it != "android" && it != "com" && it.length > 2 } ?: "Music"
                        "${appPart.replaceFirstChar { it.uppercase() }} Music"
                    }
                    packageName.contains("player", ignoreCase = true) -> "Media Player"
                    packageName.contains("audio", ignoreCase = true) -> "Audio Player"
                    packageName.contains("podcast", ignoreCase = true) -> "Podcast"
                    else -> "Media Player"
                }
            }
        }
    }
    
    private fun seekToPosition(position: Long): Boolean {
        return try {
            val mediaSessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
            val sessionTokens = mediaSessionManager?.getActiveSessions(ComponentName(this, MediaNotificationListener::class.java))
            
            if (sessionTokens.isNullOrEmpty()) {
                Log.d(TAG, "seekToPosition: No active media sessions")
                return false
            }
            
            val controller = sessionTokens[0]
            val transportControls = controller.transportControls
            
            transportControls.seekTo(position)
            Log.d(TAG, "seekToPosition: Seeked to $position ms")
            true
        } catch (e: Exception) {
            Log.e(TAG, "seekToPosition failed: ${e.message}")
            false
        }
    }
    
    private fun setPlaybackState(playing: Boolean): Boolean {
        return try {
            val mediaSessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
            val sessionTokens = mediaSessionManager?.getActiveSessions(ComponentName(this, MediaNotificationListener::class.java))
            
            if (sessionTokens.isNullOrEmpty()) {
                Log.d(TAG, "setPlaybackState: No active media sessions")
                return false
            }
            
            val controller = sessionTokens[0]
            val transportControls = controller.transportControls
            
            if (playing) {
                transportControls.play()
                Log.d(TAG, "setPlaybackState: Sent play command")
            } else {
                transportControls.pause()
                Log.d(TAG, "setPlaybackState: Sent pause command")
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "setPlaybackState failed: ${e.message}")
            false
        }
    }
}
