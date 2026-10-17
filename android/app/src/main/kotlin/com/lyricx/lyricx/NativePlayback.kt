package com.lyricx.lyricx

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.SystemClock

/** Resolves playback from Android, even when the Flutter activity/engine is gone. */
object NativePlayback {
    fun song(controller: MediaController): NativeSong? {
        val metadata = controller.metadata ?: return null
        val state = controller.playbackState ?: return null
        if (state.state !in listOf(PlaybackState.STATE_PLAYING, PlaybackState.STATE_PAUSED,
                PlaybackState.STATE_BUFFERING, PlaybackState.STATE_CONNECTING)) return null
        val playing = state.state == PlaybackState.STATE_PLAYING
        val elapsed = if (playing && state.lastPositionUpdateTime > 0)
            ((SystemClock.elapsedRealtime() - state.lastPositionUpdateTime).coerceAtLeast(0) * state.playbackSpeed).toLong()
            else 0L
        val duration = metadata.getLong(MediaMetadata.METADATA_KEY_DURATION)
        val position = (state.position + elapsed).coerceAtLeast(0)
        return NativeSong(metadata.getString(MediaMetadata.METADATA_KEY_TITLE) ?: "",
            metadata.getString(MediaMetadata.METADATA_KEY_ARTIST)
                ?: metadata.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST) ?: "",
            controller.packageName, playing,
            if (duration > 0) position.coerceAtMost(duration) else position, duration)
    }

    fun current(context: Context): NativeSong? = try {
        val manager = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
        NativeSong.select(manager.getActiveSessions(ComponentName(context, MediaNotificationListener::class.java))
            .mapNotNull(::song), context.packageName)
    } catch (_: SecurityException) { null }
}
