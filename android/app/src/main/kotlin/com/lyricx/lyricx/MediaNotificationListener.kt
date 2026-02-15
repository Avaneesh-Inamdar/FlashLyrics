package com.lyricx.lyricx

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

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
            "com.google.android.apps.youtube.music",
            "app.revanced.android.youtube.music",
            "com.google.android.youtube",  // Regular YouTube (background play)
            "com.apple.android.music",
            "com.amazon.mp3",
            "com.soundcloud.android",
            "deezer.android.app",
            "com.pandora.android",
            "com.aspiro.tidal",
            "com.tidal.music",
            
            // Regional streaming
            "com.jio.media.jiobeats",  // JioSaavn
            "com.gaana",
            "com.bsbportal.music",  // Wynk Music
            "com.hungama.myplay.activity",
            "com.qobuz.music",
            
            // Device default players
            "com.sec.android.app.music",
            "com.samsung.android.app.music",
            "com.google.android.music",
            "com.android.music",
            "com.miui.player",  // Xiaomi
            "com.oppo.music",
            "com.oneplus.music",
            "com.huawei.music",
            
            // Third-party players
            "org.videolan.vlc",
            "com.maxmpz.audioplayer",  // Poweramp
            "in.krosbits.musicolet",
            "com.jrtstudio.music",  // Rocket Player
            "com.doubletwist.androidplayer",
            "com.neutroncode.mp",  // Neutron
            "com.bandcamp.android",
            
            // Other
            "com.audible.application",
            "org.kde.kdeconnect_tp",
            "com.foobar2000.foobar2000"
        )
        
        // Static listener for Flutter communication
        var mediaUpdateListener: MediaUpdateListener? = null
        
        // Check if service is running
        var isRunning = false
            private set

        // Current song data for retrieval on app restart
        var currentTitle: String? = null
            private set
        var currentArtist: String? = null
            private set
        var currentAlbum: String? = null
            private set
        var currentArtworkUrl: String? = null
            private set
        var currentDuration: Long = 0
            private set
        var currentSource: String? = null
            private set
        var currentIsPlaying: Boolean = false
            private set

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
                "isPlaying" to currentIsPlaying
            )
        }

        // Reference to the service instance for refresh calls
        private var serviceInstance: MediaNotificationListener? = null

        // Force refresh active sessions (called when Flutter reconnects)
        fun refreshActiveSessions() {
            // Clear debounce to allow re-notification
            serviceInstance?.lastNotifiedSong = null
            serviceInstance?.checkActiveSessions()
        }
    }
    
    private var mediaSessionManager: MediaSessionManager? = null
    private var activeControllers = mutableMapOf<String, MediaController>()
    private val handler = Handler(Looper.getMainLooper())
    private var lastNotifiedSong: String? = null
    
    interface MediaUpdateListener {
        fun onMediaUpdate(title: String?, artist: String?, album: String?, 
                         artworkUrl: String?, duration: Long, source: String?, isPlaying: Boolean)
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
        // Additional check for apps that have media sessions but aren't in our list
        return packageName.contains("music") || 
               packageName.contains("audio") || 
               packageName.contains("player")
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
                    } else if (state?.state == PlaybackState.STATE_PAUSED || 
                               state?.state == PlaybackState.STATE_STOPPED) {
                        // Still notify with playing = false
                        extractAndNotifyMetadata(controller, packageName)
                    }
                }
            }
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
        
        // Get album art URI if available
        val artworkUri = metadata.getString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI)
            ?: metadata.getString(MediaMetadata.METADATA_KEY_ART_URI)
        
        if (title.isNullOrEmpty() || artist.isNullOrEmpty()) {
            Log.d(TAG, "Incomplete metadata, skipping")
            return
        }
        
        // Debounce - don't notify for same song repeatedly
        val songKey = "$title|$artist|$isPlaying"
        if (songKey == lastNotifiedSong) {
            return
        }
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
        
        Log.d(TAG, "Notifying: $title by $artist from $source (playing: $isPlaying)")
        mediaUpdateListener?.onMediaUpdate(
            title, artist, album, artworkUri, duration, source, isPlaying
        )
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
