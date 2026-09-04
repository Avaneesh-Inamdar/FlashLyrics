package com.lyricx.lyricx

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
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

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        MusicNotificationManager.createNotificationChannel(this)
        MusicNotificationManager.ensureListenerBound(this)
        // Restore overlay cache from prefs
        try {
            val prefs = getSharedPreferences("overlay_cache", Context.MODE_PRIVATE)
            val t = prefs.getString("title", "") ?: ""
            val a = prefs.getString("artist", "") ?: ""
            val l = prefs.getString("lrc", "") ?: ""
            val p = prefs.getString("plain", "") ?: ""
            val o = prefs.getInt("offset", 0) ?: 0
            val seek = prefs.getBoolean("seekEnabled", false)
            if (t.isNotEmpty() && a.isNotEmpty()) OverlayLyricsCache.update(t, a, l, p, o, seek)
        } catch (_: Exception) {}
        // If launched from music notification, handle auto-show
        handleNotificationIntent(intent)
        // High refresh rate fix: prefer the highest available refresh rate mode.
        // On devices with 90/120Hz panels Flutter otherwise may be throttled to 60Hz
        // if the window doesn't explicitly request a high-refresh mode.
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                val display = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                    display
                } else {
                    @Suppress("DEPRECATION")
                    windowManager.defaultDisplay
                }
                val modes = display?.supportedModes
                if (modes != null && modes.isNotEmpty()) {
                    val activeMode = display.mode
                    var bestMode = activeMode
                    for (m in modes) {
                        // Prefer same resolution as active mode but higher refresh
                        if (m.physicalWidth == activeMode.physicalWidth &&
                            m.physicalHeight == activeMode.physicalHeight) {
                            if (m.refreshRate > bestMode.refreshRate) {
                                bestMode = m
                            }
                        }
                    }
                    // Also consider overall highest refresh if no resolution match
                    if (bestMode.refreshRate == activeMode.refreshRate) {
                        for (m in modes) {
                            if (m.refreshRate > bestMode.refreshRate) bestMode = m
                        }
                    }
                    if (bestMode.modeId != activeMode.modeId) {
                        val attrs = window.attributes
                        attrs.preferredDisplayModeId = bestMode.modeId
                        window.attributes = attrs
                        Log.d(TAG, "High-refresh: selected mode ${bestMode.modeId} @ ${bestMode.refreshRate}Hz (was ${activeMode.modeId} @ ${activeMode.refreshRate}Hz)")
                    } else {
                        Log.d(TAG, "High-refresh: keeping mode ${activeMode.modeId} @ ${activeMode.refreshRate}Hz, best ${bestMode.refreshRate}Hz")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set preferred display mode", e)
        }
    }
    
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
                "skipToNext" -> {
                    val success = skipToNext()
                    result.success(success)
                }
                "skipToPrevious" -> {
                    val success = skipToPrevious()
                    result.success(success)
                }
                // Overlay / PiP controls
                "showOverlay" -> {
                    val hasPermission = checkOverlayPermission()
                    if (!hasPermission) {
                        result.error("NO_PERMISSION", "Overlay permission not granted", null)
                    } else {
                        val title = call.argument<String>("title") ?: ""
                        val artist = call.argument<String>("artist") ?: ""
                        val lyrics = call.argument<String>("lyrics") ?: ""
                        val currentLine = call.argument<String>("currentLine") ?: ""
                        val lrc = call.argument<String>("lrcLyrics") ?: call.argument<String>("lrc") ?: ""
                        val offset = (call.argument<Int>("syncOffsetMs") ?: 0)
                        val seekEnabled = call.argument<Boolean>("enableSeek") ?: false
                        showLyricsOverlay(title, artist, lyrics, currentLine, lrc, offset, seekEnabled)
                        result.success(true)
                    }
                }
                "hideOverlay" -> {
                    hideLyricsOverlay()
                    result.success(true)
                }
                "updateOverlayLyrics" -> {
                    val currentLine = call.argument<String>("currentLine") ?: ""
                    val nextLine = call.argument<String>("nextLine") ?: ""
                    updateOverlayLyrics(currentLine, nextLine)
                    result.success(true)
                }
                "enterPipMode" -> {
                    val success = enterPipMode()
                    result.success(success)
                }
                "checkPostNotificationPermission" -> {
                    val granted = if (Build.VERSION.SDK_INT >= 33) {
                        ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
                    } else true
                    result.success(granted)
                }
                "requestPostNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33) {
                        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1002)
                    }
                    result.success(null)
                }
                "cacheOverlayLyrics" -> {
                    val title = call.argument<String>("title") ?: ""
                    val artist = call.argument<String>("artist") ?: ""
                    val lrc = call.argument<String>("lrcLyrics") ?: ""
                    val plain = call.argument<String>("plainLyrics") ?: ""
                    val offset = call.argument<Int>("syncOffsetMs") ?: 0
                    val seekEnabled = call.argument<Boolean>("enableSeek") ?: OverlayLyricsCache.seekEnabled
                    OverlayLyricsCache.update(title, artist, lrc, plain, offset, seekEnabled)
                    // Also persist to prefs for after reboot
                    try {
                        getSharedPreferences("overlay_cache", Context.MODE_PRIVATE).edit()
                            .putString("title", title)
                            .putString("artist", artist)
                            .putString("lrc", lrc)
                            .putString("plain", plain)
                            .putInt("offset", offset)
                            .putBoolean("seekEnabled", seekEnabled)
                            .apply()
                    } catch (_: Exception) {}
                    result.success(true)
                }
                "clearOverlayCache" -> {
                    OverlayLyricsCache.update("", "", "", "", 0)
                    result.success(true)
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
            
            // Extract album art - try URI first, then bitmap with comprehensive key fallback
            // On Android 10+ some apps store art under different keys
            var artworkUrl: String? = metadata.getString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI)
                ?: metadata.getString(MediaMetadata.METADATA_KEY_ART_URI)
                ?: metadata.getString(MediaMetadata.METADATA_KEY_DISPLAY_ICON_URI)
            
            // If URI is a content:// URI, try to cache it as a file for older Android compatibility
            if (!artworkUrl.isNullOrEmpty() && artworkUrl.startsWith("content://")) {
                val cached = cacheContentUri(artworkUrl, title, artist)
                if (cached != null) artworkUrl = cached
                // Keep original content:// as fallback if caching fails, Dart will try network fallback
            }
            
            // If no URI or URI caching didn't produce file, try to get bitmap and cache it
            if (artworkUrl.isNullOrEmpty() || artworkUrl.startsWith("content://")) {
                // Try multiple bitmap keys for maximum compatibility
                var bitmap: Bitmap? = null
                try {
                    bitmap = metadata.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                    if (bitmap == null) bitmap = metadata.getBitmap(MediaMetadata.METADATA_KEY_ART)
                    if (bitmap == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        bitmap = metadata.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
                    }
                    // Some Samsung/MIUI devices store art as display icon
                    if (bitmap == null) {
                        @Suppress("DEPRECATION")
                        bitmap = metadata.getBitmap("android.media.metadata.ALBUM_ART")
                    }
                } catch (_: Exception) {}
                if (bitmap != null) {
                    val cachedBitmap = cacheArtworkBitmap(bitmap, title, artist)
                    if (cachedBitmap != null) artworkUrl = cachedBitmap
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
            
            // Keep music notification in sync even when direct querying
            MusicNotificationManager.showMusicNotification(
                this, title, artist, source, isPlaying, bestController.packageName
            )
            
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
                .take(64)
            val file = File(cacheDir, "art_direct_${safeName}.png")
            // Re-write if file missing or bitmap differs (check size)
            // On Android 10+ ensure we handle large bitmaps by scaling down to 600x600 max
            var bmpToSave = bitmap
            val maxDim = 700
            if (bitmap.width > maxDim || bitmap.height > maxDim) {
                val ratio = minOf(maxDim.toFloat() / bitmap.width, maxDim.toFloat() / bitmap.height)
                val newW = (bitmap.width * ratio).toInt()
                val newH = (bitmap.height * ratio).toInt()
                bmpToSave = Bitmap.createScaledBitmap(bitmap, newW, newH, true)
            }
            // Always write to ensure fresh art; delete stale file first
            if (file.exists()) file.delete()
            FileOutputStream(file).use { out ->
                bmpToSave.compress(Bitmap.CompressFormat.JPEG, 85, out)
            }
            if (bmpToSave != bitmap) bmpToSave.recycle()
            "file://${file.absolutePath}"
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
                .take(64)
            val uri = Uri.parse(uriString)
            val input = contentResolver.openInputStream(uri) ?: return null
            val file = File(cacheDir, "art_direct_${safeName}_uri.jpg")
            // overwrite previous
            if (file.exists()) file.delete()
            FileOutputStream(file).use { out ->
                input.copyTo(out)
            }
            try { input.close() } catch (_: Exception) {}
            "file://${file.absolutePath}"
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cache content URI art: $uriString", e)
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
            
            val controller = selectBestController(sessionTokens)
                ?: return false
            val transportControls = controller.transportControls
            
            if (playing) {
                transportControls.play()
                Log.d(TAG, "setPlaybackState: Sent play command to ${controller.packageName}")
            } else {
                transportControls.pause()
                Log.d(TAG, "setPlaybackState: Sent pause command to ${controller.packageName}")
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "setPlaybackState failed: ${e.message}")
            false
        }
    }

    private fun skipToNext(): Boolean {
        return try {
            val msm = getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
            val controllers = msm?.getActiveSessions(ComponentName(this, MediaNotificationListener::class.java))
            if (controllers.isNullOrEmpty()) {
                Log.d(TAG, "skipToNext: No active sessions")
                return false
            }
            val controller = selectBestController(controllers) ?: return false
            controller.transportControls.skipToNext()
            Log.d(TAG, "skipToNext: Sent to ${controller.packageName}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "skipToNext failed", e)
            false
        }
    }

    private fun skipToPrevious(): Boolean {
        return try {
            val msm = getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
            val controllers = msm?.getActiveSessions(ComponentName(this, MediaNotificationListener::class.java))
            if (controllers.isNullOrEmpty()) {
                Log.d(TAG, "skipToPrevious: No active sessions")
                return false
            }
            val controller = selectBestController(controllers) ?: return false
            controller.transportControls.skipToPrevious()
            Log.d(TAG, "skipToPrevious: Sent to ${controller.packageName}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "skipToPrevious failed", e)
            false
        }
    }

    private fun selectBestController(controllers: List<android.media.session.MediaController>): android.media.session.MediaController? {
        // Prefer playing controller, otherwise first with metadata
        var best: android.media.session.MediaController? = null
        var bestPlaying = false
        for (c in controllers) {
            val isPlaying = c.playbackState?.state == PlaybackState.STATE_PLAYING
            if (isPlaying && !bestPlaying) {
                best = c
                bestPlaying = true
            } else if (best == null) {
                best = c
                bestPlaying = isPlaying
            }
        }
        return best
    }

    // --- Overlay / PiP helpers ---
    private var overlayServiceIntent: Intent? = null
    // Track if overlay was showing when app came to foreground, so we can restore on pause
    private var overlayWasShowingBeforeForeground: Boolean = false
    private var appIsInForeground: Boolean = false

    private fun showLyricsOverlay(title: String, artist: String, lyrics: String, currentLine: String, lrcLyrics: String = "", syncOffsetMs: Int = 0, seekEnabled: Boolean = OverlayLyricsCache.seekEnabled) {
        try {
            val intent = Intent(this, LyricsOverlayService::class.java).apply {
                action = LyricsOverlayService.ACTION_SHOW
                putExtra("title", title)
                putExtra("artist", artist)
                putExtra("lyrics", lyrics)
                putExtra("currentLine", currentLine)
                putExtra("lrcLyrics", lrcLyrics)
                putExtra("syncOffsetMs", syncOffsetMs)
                putExtra("enableSeek", seekEnabled)
            }
            overlayServiceIntent = intent
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            Log.d(TAG, "Overlay service started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show overlay", e)
        }
    }

    private fun hideLyricsOverlay() {
        try {
            val intent = Intent(this, LyricsOverlayService::class.java).apply {
                action = LyricsOverlayService.ACTION_HIDE
            }
            startService(intent)
            Log.d(TAG, "Overlay hide requested")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to hide overlay", e)
        }
    }

    private fun updateOverlayLyrics(currentLine: String, nextLine: String) {
        try {
            val intent = Intent(this, LyricsOverlayService::class.java).apply {
                action = LyricsOverlayService.ACTION_UPDATE
                putExtra("currentLine", currentLine)
                putExtra("nextLine", nextLine)
            }
            startService(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update overlay", e)
        }
    }

    private fun enterPipMode(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val params = android.app.PictureInPictureParams.Builder().build()
                enterPictureInPictureMode(params)
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "PIP failed", e)
            false
        }
    }

    override fun onResume() {
        super.onResume()
        appIsInForeground = true
        MusicNotificationManager.ensureListenerBound(this)
        // If overlay is currently showing, hide it while the app is visible
        if (LyricsOverlayService.isOverlayShowing) {
            overlayWasShowingBeforeForeground = true
            hideLyricsOverlay()
            Log.d(TAG, "App foregrounded — overlay hidden temporarily")
        } else {
            overlayWasShowingBeforeForeground = false
        }
    }

    override fun onPause() {
        super.onPause()
        appIsInForeground = false
        // Re-show overlay when app goes to background, if it was showing before and music is playing
        if (overlayWasShowingBeforeForeground) {
            val isPlaying = MediaNotificationListener.currentIsPlaying
            val title = MediaNotificationListener.currentTitle
            val artist = MediaNotificationListener.currentArtist
            if (isPlaying && !title.isNullOrEmpty() && !artist.isNullOrEmpty() &&
                checkOverlayPermission()) {
                val lrc = OverlayLyricsCache.lrc
                val plain = OverlayLyricsCache.plain
                val offset = OverlayLyricsCache.syncOffsetMs
                val seek = OverlayLyricsCache.seekEnabled
                showLyricsOverlay(title, artist, plain, "", lrc, offset, seek)
                Log.d(TAG, "App backgrounded — overlay restored for $title by $artist")
            }
            overlayWasShowingBeforeForeground = false
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleNotificationIntent(intent)
    }

    private fun handleNotificationIntent(intent: Intent?) {
        if (intent == null) return
        val autoShow = intent.getBooleanExtra("autoShowOverlay", false)
        if (!autoShow) return
        val title = intent.getStringExtra("title") ?: OverlayLyricsCache.title
        val artist = intent.getStringExtra("artist") ?: OverlayLyricsCache.artist
        if (title.isEmpty() || artist.isEmpty()) return
        // Defer slightly to ensure Flutter engine ready
        window.decorView.postDelayed({
            val lrc = OverlayLyricsCache.lrc
            val plain = OverlayLyricsCache.plain
            val offset = OverlayLyricsCache.syncOffsetMs
            val seek = OverlayLyricsCache.seekEnabled
            val lyrics = if (lrc.isNotEmpty()) lrc else plain
            if (Settings.canDrawOverlays(this) && lyrics.isNotEmpty()) {
                showLyricsOverlay(title, artist, plain, "", lrc, offset, seek)
            } else {
                // No cached lyrics yet - just ensure app is visible; Flutter will fetch
                Log.d(TAG, "No cached lyrics for $title, opening app for fetch")
            }
        }, 800)
    }
}
