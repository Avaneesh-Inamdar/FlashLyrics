package com.lyricx.lyricx

import java.text.Normalizer
import java.util.Locale

data class NativeSong(
    val title: String,
    val artist: String,
    val packageName: String,
    val playing: Boolean,
    val position: Long = 0,
    val duration: Long = 0
) {
    fun matches(title: String, artist: String): Boolean =
        key(this.title) == key(title) && key(this.artist) == key(artist)

    companion object {
        fun key(value: String): String = Normalizer.normalize(value, Normalizer.Form.NFKC)
            .trim().lowercase(Locale.ROOT).replace(Regex("[^\\p{L}\\p{M}\\p{N}]+"), "_").trim('_')

        fun select(songs: List<NativeSong>, ownPackage: String): NativeSong? {
            val usable = songs.filter { it.packageName != ownPackage &&
                key(it.title).isNotEmpty() && key(it.artist).isNotEmpty() }
            return usable.firstOrNull { it.playing } ?: usable.firstOrNull()
        }
    }
}
