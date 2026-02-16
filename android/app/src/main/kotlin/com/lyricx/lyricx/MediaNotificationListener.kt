package com.lyricx.lyricx

import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Service that listens for media notifications and extracts currently playing song metadata.
 * Detects music from Spotify, YouTube Music, Apple Music, and system media players.
 */
class MediaNotificationListener : NotificationListenerService() {
    
    companion object {
        private const val TAG = "MediaNotificationListener"
        
        // Supported media player packages
        private val SUPPORTED_PACKAGES = setOf(
            // Major streaming services
            "com.spotify.music",
            "com.spotify.lite",
            "com.google.android.apps.youtube.music",
            "app.revanced.android.youtube.music",
            "com.google.android.youtube",
            "com.apple.android.music",
            "com.amazon.mp3",
            "com.soundcloud.android",
            "deezer.android.app",
            "com.pandora.android",
            "com.aspiro.tidal",
            "com.tidal.music",
            "com.clearchannel.iheartradio.controller",
            "tunein.player",
            "com.audiomack",
            "com.mixcloud.player",
            "fm.last.android",
            
            // Regional streaming
            "com.jio.media.jiobeats",
            "com.gaana",
            "com.bsbportal.music",
            "com.hungama.myplay.activity",
            "com.qobuz.music",
            "com.resso.app",
            "com.resso.music",
            "com.anghami",
            "com.boomplay.music",
            "com.yandex.music",
            "com.tencent.qqmusic",
            "com.netease.cloudmusic",
            "com.kugou.android",
            "com.kuwo.player",
            "jp.linecorp.linemusic",
            "com.naver.vibe",
            "com.iloen.melon",
            
            // Device default players
            "com.sec.android.app.music",
            "com.samsung.android.app.music",
            "com.google.android.music",
            "com.android.music",
            "com.miui.player",
            "com.oppo.music",
            "com.oneplus.music",
            "com.huawei.music",
            "com.transsion.music",
            "com.realme.music",
            "com.vivo.music",
            
            // Third-party players
            "org.videolan.vlc",
            "com.maxmpz.audioplayer",
            "in.krosbits.musicolet",
            "com.jrtstudio.music",
            "com.doubletwist.androidplayer",
            "com.neutroncode.mp",
            "com.bandcamp.android",
            "code.name.monkey.retromusic",
            "com.tozelabs.musicplayer",
            "com.tozelabs.musicplayerf",
            "com.ympx.music",
            "player.flavor.flavor",
            "com.joythis.joymusic",
            "com.flyingdog",
            "com.nox.evermusic",
            
            // Podcasts & Other
            "com.audible.application",
            "com.google.android.apps.podcasts",
            "com.pocketcasts.android",
            "org.kde.kdeconnect_tp",
            "com.foobar2000.foobar2000",
            "com.shazam.android"
        )
        
        // Static listener for Flutter communication
        var mediaUpdateListener: MediaUpdateListener? = null
        
        // Check if service is running
        var isRunning = false
            private set

        // Current song data for retrieval on app restart
        var currentTitle: String? = null
        var currentArtist: String? = null
        var currentAlbum: String? = null
        var currentArtworkUrl: String? = null
        var currentDuration: Long = 0
        var currentSource: String? = null
        var currentIsPlaying: Boolean = false
        var currentPosition: Long = 0
        var currentPlaybackSpeed: Float = 1.0f
            private set

        // Position update interval in milliseconds
        private const val POSITION_UPDATE_INTERVAL = 150L

        // Get the current song as a map for Flutter
        fun getCurrentSong(): Map<String, Any?>? {
            if (currentTitle.isNullOrEmpty() || currentArtist.isNullOrEmpty()) {
                return null
            }
            return mapOf(
                "title" to currentTitle,
                "artist" to currentArtist,
                "album" to currentAlbum,
                "artworkUrl" to currentArtworkUrl,
                "duration" to currentDuration,
                "source" to currentSource,
                "isPlaying" to currentIsPlaying,
                "position" to currentPosition
            )
        }

        // Reference to the service instance for refresh calls
        private var serviceInstance: MediaNotificationListener? = null
        
        // Flag to force notification on next check (ignores debounce)
        private var forceNextNotification = false

        // Force refresh active sessions (called when Flutter reconnects)
        fun refreshActiveSessions() {
            // Clear debounce and force notification to allow re-notification
            serviceInstance?.lastNotifiedSong = null
            forceNextNotification = true
            serviceInstance?.checkActiveSessions()
        }
    }
    
    private var mediaSessionManager: MediaSessionManager? = null
    private var activeControllers = mutableMapOf<String, MediaController>()
    private val handler = Handler(Looper.getMainLooper())
    private var lastNotifiedSong: String? = null
    
    // Position tracking
    private var positionUpdateRunnable: Runnable? = null
    private var activePlayingController: MediaController? = null
    private var lastPositionUpdateTime: Long = 0
    private var basePosition: Long = 0
    private var playbackSpeed: Float = 1.0f
    private var isPositionTrackingActive = false
    
    interface MediaUpdateListener {
        fun onMediaUpdate(title: String?, artist: String?, album: String?, 
                         artworkUrl: String?, duration: Long, source: String?, isPlaying: Boolean,
                         position: Long)
        fun onPositionUpdate(position: Long, duration: Long, isPlaying: Boolean)
        fun onPlaybackStopped()
    }
    
    override fun onCreate() {
        super.onCreate()
        isRunning = true
        serviceInstance = this
        Log.d(TAG, "MediaNotificationListener created")
        initializeMediaSessionManager()
    }
    
    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        serviceInstance = null
        stopPositionTracking()
        cleanupControllers()
        Log.d(TAG, "MediaNotificationListener destroyed")
    }
    
    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "Listener connected")
        initializeMediaSessionManager()
        // Check for active sessions immediately
        checkActiveSessions()
    }
    
    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.d(TAG, "Listener disconnected")
        stopPositionTracking()
        cleanupControllers()
    }
    
    private fun initializeMediaSessionManager() {
        try {
            mediaSessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
            mediaSessionManager?.addOnActiveSessionsChangedListener(
                { controllers -> onActiveSessionsChanged(controllers) },
                ComponentName(this, MediaNotificationListener::class.java)
            )
        } catch (e: SecurityException) {
            Log.e(TAG, "SecurityException: Need Notification Access permission", e)
        }
    }
    
    private fun checkActiveSessions() {
        try {
            val controllers = mediaSessionManager?.getActiveSessions(
                ComponentName(this, MediaNotificationListener::class.java)
            )
            onActiveSessionsChanged(controllers)
        } catch (e: SecurityException) {
            Log.e(TAG, "Failed to get active sessions", e)
        }
    }
    
    private fun onActiveSessionsChanged(controllers: List<MediaController>?) {
        // Clear old controllers
        cleanupControllers()
        
        controllers?.forEach { controller ->
            val packageName = controller.packageName
            if (SUPPORTED_PACKAGES.contains(packageName) || isMediaApp(packageName)) {
                Log.d(TAG, "Registering controller for: $packageName")
                activeControllers[packageName] = controller
                controller.registerCallback(createCallback(packageName), handler)
                
                // Check current metadata
                extractAndNotifyMetadata(controller, packageName)
            }
        }
    }
    
    private fun isMediaApp(packageName: String): Boolean {
        // Broad check: any app that has a media session with audio-related name
        return packageName.contains("music", ignoreCase = true) || 
               packageName.contains("audio", ignoreCase = true) || 
               packageName.contains("player", ignoreCase = true) ||
               packageName.contains("radio", ignoreCase = true) ||
               packageName.contains("podcast", ignoreCase = true) ||
               packageName.contains("media", ignoreCase = true) ||
               packageName.contains("song", ignoreCase = true) ||
               packageName.contains("tune", ignoreCase = true) ||
               packageName.contains("stream", ignoreCase = true)
    }
    
    private fun createCallback(packageName: String): MediaController.Callback {
        return object : MediaController.Callback() {
            override fun onMetadataChanged(metadata: MediaMetadata?) {
                Log.d(TAG, "Metadata changed for $packageName")
                activeControllers[packageName]?.let { controller ->
                    extractAndNotifyMetadata(controller, packageName)
                }
            }
            
            override fun onPlaybackStateChanged(state: PlaybackState?) {
                Log.d(TAG, "Playback state changed for $packageName: ${state?.state}")
                activeControllers[packageName]?.let { controller ->
                    if (state?.state == PlaybackState.STATE_PLAYING) {
                        extractAndNotifyMetadata(controller, packageName)
                        startPositionTracking(controller)
                    } else if (state?.state == PlaybackState.STATE_PAUSED || 
                               state?.state == PlaybackState.STATE_STOPPED) {
                        // Still notify with playing = false
                        extractAndNotifyMetadata(controller, packageName)
                        if (state?.state == PlaybackState.STATE_PAUSED) {
                            // Update position one last time but stop tracking
                            updatePositionFromState(state)
                            stopPositionTracking()
                            // Send final position update
                            mediaUpdateListener?.onPositionUpdate(
                                currentPosition,
                                currentDuration,
                                false
                            )
                        } else {
                            stopPositionTracking()
                        }
                    }
                }
            }
        }
    }
    
    /**
     * Start periodic position tracking for the active controller.
     * Uses Handler.postDelayed to send position updates every POSITION_UPDATE_INTERVAL ms.
     */
    private fun startPositionTracking(controller: MediaController) {
        // Don't restart if already tracking the same controller
        if (isPositionTrackingActive && activePlayingController == controller) {
            return
        }
        
        stopPositionTracking()
        activePlayingController = controller
        isPositionTrackingActive = true
        
        // Initialize position from current state
        controller.playbackState?.let { state ->
            updatePositionFromState(state)
        }
        
        positionUpdateRunnable = object : Runnable {
            override fun run() {
                if (!isPositionTrackingActive) return
                
                // Calculate current position
                val currentPos = calculateCurrentPosition()
                currentPosition = currentPos
                
                // Send position update to Flutter
                mediaUpdateListener?.onPositionUpdate(
                    currentPos,
                    currentDuration,
                    currentIsPlaying
                )
                
                // Schedule next update
                if (isPositionTrackingActive && currentIsPlaying) {
                    handler.postDelayed(this, POSITION_UPDATE_INTERVAL)
                }
            }
        }
        
        // Start the periodic updates
        handler.post(positionUpdateRunnable!!)
        Log.d(TAG, "Started position tracking")
    }
    
    /**
     * Stop position tracking when playback stops or pauses.
     */
    private fun stopPositionTracking() {
        isPositionTrackingActive = false
        positionUpdateRunnable?.let { handler.removeCallbacks(it) }
        positionUpdateRunnable = null
        activePlayingController = null
        Log.d(TAG, "Stopped position tracking")
    }
    
    /**
     * Update base position values from PlaybackState.
     * Called when PlaybackState changes to sync our tracking.
     */
    private fun updatePositionFromState(state: PlaybackState) {
        basePosition = state.position
        lastPositionUpdateTime = state.lastPositionUpdateTime
        playbackSpeed = state.playbackSpeed
        currentPlaybackSpeed = playbackSpeed
        
        // Handle apps that report 0 or negative speed
        if (playbackSpeed <= 0) {
            playbackSpeed = 1.0f
        }
        
        Log.d(TAG, "Position state updated: pos=$basePosition, speed=$playbackSpeed")
    }
    
    /**
     * Calculate the current playback position based on elapsed time.
     * Formula: position + (currentTime - lastUpdateTime) * playbackSpeed
     * 
     * This handles apps that don't update position frequently by extrapolating
     * from the last known position.
     */
    private fun calculateCurrentPosition(): Long {
        if (!currentIsPlaying) {
            return basePosition
        }
        
        // Get fresh state if available
        activePlayingController?.playbackState?.let { state ->
            // If the state has been updated recently, use it directly
            if (state.lastPositionUpdateTime > lastPositionUpdateTime) {
                updatePositionFromState(state)
            }
        }
        
        val currentTime = SystemClock.elapsedRealtime()
        val elapsedSinceUpdate = currentTime - lastPositionUpdateTime
        
        // Calculate extrapolated position
        val calculatedPosition = basePosition + (elapsedSinceUpdate * playbackSpeed).toLong()
        
        // Clamp to valid range (0 to duration)
        return when {
            calculatedPosition < 0 -> 0
            currentDuration > 0 && calculatedPosition > currentDuration -> currentDuration
            else -> calculatedPosition
        }
    }
    
    private fun extractAndNotifyMetadata(controller: MediaController, packageName: String) {
        val metadata = controller.metadata ?: return
        val playbackState = controller.playbackState
        val isPlaying = playbackState?.state == PlaybackState.STATE_PLAYING
        
        val title = metadata.getString(MediaMetadata.METADATA_KEY_TITLE)
        val artist = metadata.getString(MediaMetadata.METADATA_KEY_ARTIST) 
                  ?: metadata.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
        val album = metadata.getString(MediaMetadata.METADATA_KEY_ALBUM)
        val duration = metadata.getLong(MediaMetadata.METADATA_KEY_DURATION)
        
        // Get album art URI or bitmap if available
        var artworkUri = metadata.getString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI)
            ?: metadata.getString(MediaMetadata.METADATA_KEY_ART_URI)
        val artworkBitmap = metadata.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_ART)
        
        // Get current position from playback state
        val position = playbackState?.position ?: 0L
        
        if (title.isNullOrEmpty() || artist.isNullOrEmpty()) {
            Log.d(TAG, "Incomplete metadata, skipping")
            return
        }

        if (!artworkUri.isNullOrEmpty() && artworkUri.startsWith("content://")) {
            artworkUri = cacheArtworkUri(artworkUri, title, artist) ?: artworkUri
        }

        if (artworkUri.isNullOrEmpty() && artworkBitmap != null) {
            artworkUri = cacheArtworkBitmap(artworkBitmap, title, artist)
        }
        
        // Debounce - only skip if exact same notification (include position range to avoid spam)
        // Include isPlaying so we notify when playback state changes
        val songKey = "$title|$artist"
        val isSameSong = songKey == lastNotifiedSong
        
        // For same song, only notify if playback state changed or it's a fresh app connection
        // Always notify if forceNextNotification is set (happens when Flutter reconnects)
        if (isSameSong && isPlaying == currentIsPlaying && mediaUpdateListener != null && !forceNextNotification) {
            // Same song, same playback state, skip to avoid spam
            // But still start position tracking if playing
            if (isPlaying) {
                startPositionTracking(controller)
            }
            return
        }
        
        // Reset force flag after we use it
        forceNextNotification = false
        lastNotifiedSong = songKey
        
        // Get friendly source name
        val source = getSourceName(packageName)
        
        // Store current song data for retrieval on app restart
        currentTitle = title
        currentArtist = artist
        currentAlbum = album
        currentArtworkUrl = artworkUri
        currentDuration = duration
        currentSource = source
        currentIsPlaying = isPlaying
        currentPosition = position
        
        // Update position tracking state if we have playback state
        playbackState?.let { updatePositionFromState(it) }
        
        // Start position tracking if song is playing
        if (isPlaying) {
            startPositionTracking(controller)
        }
        
        Log.d(TAG, "Notifying: $title by $artist from $source (playing: $isPlaying, pos: ${position}ms)")
        mediaUpdateListener?.onMediaUpdate(
            title, artist, album, artworkUri, duration, source, isPlaying, position
        )
    }

    private fun cacheArtworkBitmap(bitmap: Bitmap, title: String, artist: String): String? {
        return try {
            val safeName = ("${title}_${artist}")
                .lowercase()
                .replace(Regex("[^a-z0-9_]+"), "_")
                .trim('_')
            val file = File(cacheDir, "art_$safeName.png")
            FileOutputStream(file).use { out ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 90, out)
            }
            file.toURI().toString()
        } catch (e: IOException) {
            Log.e(TAG, "Failed to cache album art bitmap", e)
            null
        }
    }

    private fun cacheArtworkUri(uriString: String, title: String, artist: String): String? {
        return try {
            val safeName = ("${title}_${artist}")
                .lowercase()
                .replace(Regex("[^a-z0-9_]+"), "_")
                .trim('_')
            val uri = Uri.parse(uriString)
            val input = contentResolver.openInputStream(uri) ?: return null
            val file = File(cacheDir, "art_${safeName}_uri.png")
            FileOutputStream(file).use { out ->
                input.copyTo(out)
            }
            input.close()
            file.toURI().toString()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cache album art uri", e)
            null
        }
    }
    
    private fun getSourceName(packageName: String): String {
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
            
            // Device players
            "com.sec.android.app.music", "com.samsung.android.app.music" -> "Samsung Music"
            "com.google.android.music" -> "Google Play Music"
            "com.miui.player" -> "Mi Music"
            "com.oppo.music" -> "OPPO Music"
            "com.oneplus.music" -> "OnePlus Music"
            "com.huawei.music" -> "Huawei Music"
            
            // Third-party
            "org.videolan.vlc" -> "VLC"
            "com.maxmpz.audioplayer" -> "Poweramp"
            "in.krosbits.musicolet" -> "Musicolet"
            "com.jrtstudio.music" -> "Rocket Player"
            "com.doubletwist.androidplayer" -> "doubleTwist"
            "com.neutroncode.mp" -> "Neutron"
            "com.bandcamp.android" -> "Bandcamp"
            "com.audible.application" -> "Audible"
            "com.foobar2000.foobar2000" -> "foobar2000"
            
            else -> "Media Player"
        }
    }
    
    private fun cleanupControllers() {
        activeControllers.forEach { (_, controller) ->
            try {
                // Unregister callbacks if possible
            } catch (e: Exception) {
                Log.e(TAG, "Error cleaning up controller", e)
            }
        }
        activeControllers.clear()
    }
    
    // Handle notification posted (fallback for some players)
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        sbn?.let {
            if (SUPPORTED_PACKAGES.contains(it.packageName)) {
                // Trigger session check when media notification posted
                handler.postDelayed({ checkActiveSessions() }, 100)
            }
        }
    }
}
