package com.lyricx.lyricx

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSession
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Looper
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class NativePlaybackTest {
    private lateinit var context: Context
    private lateinit var manager: MediaSessionManager
    private val sessions = mutableListOf<MediaSession>()

    @Before fun setup() {
        context = RuntimeEnvironment.getApplication()
        manager = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
        MusicNotificationManager.cancelMusicNotification(context)
        OverlayLyricsCache.update("", "", "", "", 0)
        MediaNotificationListener.mediaUpdateListener = null
    }
    @After fun cleanup() { sessions.forEach { it.release() }; shadowOf(manager).clearControllers() }

    private fun metadata(title: String, artist: String = "Artist") = MediaMetadata.Builder()
        .putString(MediaMetadata.METADATA_KEY_TITLE, title)
        .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
        .putLong(MediaMetadata.METADATA_KEY_DURATION, 180000).build()

    private fun player(title: String, pkg: String, playing: Boolean): MediaController {
        val session = MediaSession(context, title).also { sessions.add(it) }
        return MediaController(context, session.sessionToken).also {
            shadowOf(it).setPackageName(pkg)
            shadowOf(it).setMetadata(metadata(title))
            shadowOf(it).setPlaybackState(PlaybackState.Builder().setState(
                if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED, 1000, 1f).build())
            shadowOf(manager).addController(it)
        }
    }

    @Test fun floatResolvesLiveSessionInsteadOfLastViewedLyrics() {
        player("Old paused song", "com.google.android.apps.youtube.music", false)
        player("Current song", "com.spotify.music", true)
        OverlayLyricsCache.update("Old paused song", "Artist", "[00:01]Wrong lyrics", "Wrong lyrics", 0)
        val intent = NativeOverlayIntent.forCurrentSong(context)!!
        assertEquals("Current song", intent.getStringExtra("title"))
        assertEquals("", intent.getStringExtra("lyrics"))
        assertEquals("", intent.getStringExtra("lrcLyrics"))
    }

    @Test fun notificationAndMetadataKeepUpdatingWithoutFlutter() {
        val active = player("First", "com.spotify.music", true)
        player("Paused elsewhere", "com.google.android.apps.youtube.music", false)
        val lifecycle = Robolectric.buildService(MediaNotificationListener::class.java).create()
        val service = lifecycle.get()
        service.onListenerConnected()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("First", MediaNotificationListener.currentTitle)
        OverlayLyricsCache.update("First", "Artist", "[00:01]First lyrics", "First lyrics", 0)
        shadowOf(active).executeOnMetadataChanged(metadata("Second"))
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("Second", MediaNotificationListener.currentTitle)
        assertFalse(OverlayLyricsCache.hasLyrics())
        val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        assertEquals("Second", shadowOf(notifications).getNotification(2002).extras.getString(Notification.EXTRA_TITLE))
        assertEquals(1, shadowOf(active).callbacks.size)
        service.onListenerConnected()
        assertEquals(1, shadowOf(active).callbacks.size)
        service.onListenerDisconnected()
        assertNull(shadowOf(notifications).getNotification(2002))
        assertNull(MediaNotificationListener.currentTitle)
        assertEquals(0, shadowOf(active).callbacks.size)
        service.onListenerConnected()
        assertEquals("Second", MediaNotificationListener.currentTitle)
        lifecycle.destroy()
        assertEquals(0, shadowOf(active).callbacks.size)
    }

    @Test fun floatDoesNotResurrectNotificationWhenNoPlayerExists() {
        OverlayLyricsCache.update("Yesterday", "Artist", "", "Old lyrics", 0)
        assertNull(NativeOverlayIntent.forCurrentSong(context))
    }

    @Test fun nativeOfflineLookupIgnoresUnrelatedSavedSongs() {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit().putString("flutter.lyrics_cache", JSONObject().put("random-id", JSONObject()
            .put("trackName", "Actual song").put("artistName", "Artist")
            .put("plainLyrics", "Saved lyrics").put("lrcLyrics", "[00:01]Saved lyrics")).toString()).commit()
        val wanted = NativeSong("Actual song", "Artist", "com.spotify.music", true)
        assertEquals("Saved lyrics", NativeLyricsLoader.cached(context, wanted)!!.plain)
        assertNull(NativeLyricsLoader.cached(context, wanted.copy(title = "Different song")))
    }

    @Test fun fallbackRejectsWrongProviderMetadataAndEmptyResults() {
        val wanted = NativeSong("Song", "Artist", "com.spotify.music", true)
        val result = JSONObject().put("trackName", "Song").put("artistName", "Other artist").put("plainLyrics", "Wrong")
        assertNull(NativeLyricsLoader.result(wanted, result, 100))
        result.put("artistName", "Artist")
        assertEquals(100, NativeLyricsLoader.result(wanted, result, 100)!!.offset)
        result.put("plainLyrics", JSONObject.NULL)
        assertNull(NativeLyricsLoader.result(wanted, result, 0))
    }

    @Test fun offsetAndSeekOptionsSurviveProcessRestartForUnicodeSongs() {
        val wanted = NativeSong("गीत", "कलाकार", "com.spotify.music", true)
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit().putString("flutter.app_settings", "{\"lyricsSyncOffset\":200,\"floatingOverlaySeekEnabled\":true}")
            .putString("flutter.song_lyrics_offsets", "{\"कलाकार_गीत\":-600}").commit()
        assertEquals(-600 to true, NativeLyricsLoader.options(context, wanted))
    }

    @Test fun playbackSelectionExcludesOwnSessionAndIncompleteTracks() {
        val own = NativeSong("Own", "Artist", "music.flashlyrics.app", true)
        val bad = NativeSong("", "Artist", "com.spotify.music", true)
        val good = NativeSong("歌", "歌手", "com.apple.android.music", true)
        assertEquals(good, NativeSong.select(listOf(own, bad, good), own.packageName))
        assertFalse(good.matches("別の歌", "歌手"))
    }
}
