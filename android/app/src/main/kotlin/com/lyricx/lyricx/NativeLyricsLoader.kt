package com.lyricx.lyricx

import android.content.Context
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/** Bounded overlay fallback. Runs on the overlay worker, never on the UI thread. */
object NativeLyricsLoader {
    fun options(context: Context, song: NativeSong): Pair<Int, Boolean> {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val settings = json(prefs.getString("flutter.app_settings", null))
        val offsets = json(prefs.getString("flutter.song_lyrics_offsets", null))
        val key = "${NativeSong.key(song.artist)}_${NativeSong.key(song.title)}"
        val offset = if (offsets.has(key)) offsets.optInt(key) else settings.optInt("lyricsSyncOffset", 0)
        return offset to settings.optBoolean("floatingOverlaySeekEnabled", false)
    }

    fun cached(context: Context, song: NativeSong): OverlayLyricsCache.Entry? {
        OverlayLyricsCache.forSong(song)?.takeIf { it.lrc.isNotBlank() || it.plain.isNotBlank() }?.let { return it }
        val stored = context.getSharedPreferences("overlay_cache", Context.MODE_PRIVATE)
        if (song.matches(stored.getString("title", "") ?: "", stored.getString("artist", "") ?: "")) {
            val entry = OverlayLyricsCache.Entry(song.title, song.artist,
                stored.getString("lrc", "") ?: "", stored.getString("plain", "") ?: "", options(context, song).first)
            if (entry.lrc.isNotBlank() || entry.plain.isNotBlank()) return entry
        }
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val library = json(prefs.getString("flutter.lyrics_cache", null))
        for (key in library.keys()) {
            val item = library.optJSONObject(key) ?: continue
            // Do not trust legacy IDs or a last-viewed manual selection.
            if (!song.matches(item.optString("trackName"), item.optString("artistName"))) continue
            val lrc = item.optString("lrcLyrics", "").takeUnless { it == "null" } ?: ""
            val plain = item.optString("plainLyrics", "")
            if (lrc.isNotBlank() || plain.isNotBlank()) return OverlayLyricsCache.Entry(song.title, song.artist,
                lrc, plain, options(context, song).first)
        }
        return null
    }

    fun fetch(context: Context, song: NativeSong): OverlayLyricsCache.Entry? {
        cached(context, song)?.let { return it }
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val settings = json(prefs.getString("flutter.app_settings", null))
        val priority = settings.optJSONArray("providerPriority")
        if (priority != null && (0 until priority.length()).none { priority.optString(it) == "lrclib" }) return null
        val query = "artist_name=${encode(song.artist)}&track_name=${encode(song.title)}"
        val connection = URL("https://lrclib.net/api/get?$query").openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 4000
            connection.readTimeout = 5000
            connection.setRequestProperty("User-Agent", "FlashLyrics/1.4.3 (https://github.com/Avaneesh-Inamdar/FlashLyrics)")
            if (connection.responseCode != 200) return null
            val body = connection.inputStream.use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(8192)
                while (output.size() <= 1024 * 1024) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
            if (body.size > 1024 * 1024) return null
            return result(song, JSONObject(String(body, Charsets.UTF_8)), options(context, song).first)
        } finally { connection.disconnect() }
    }

    internal fun result(song: NativeSong, data: JSONObject, offset: Int): OverlayLyricsCache.Entry? {
        if (!song.matches(data.optString("trackName"), data.optString("artistName"))) return null
        val lrc = data.optString("syncedLyrics", "").takeUnless { it == "null" } ?: ""
        val plain = data.optString("plainLyrics", "").takeUnless { it == "null" } ?: ""
        return if (lrc.isBlank() && plain.isBlank()) null else OverlayLyricsCache.Entry(song.title, song.artist, lrc, plain, offset)
    }

    private fun json(raw: String?): JSONObject = try { JSONObject(raw ?: "{}") } catch (_: Exception) { JSONObject() }
    private fun encode(value: String) = URLEncoder.encode(value, "UTF-8")
}
