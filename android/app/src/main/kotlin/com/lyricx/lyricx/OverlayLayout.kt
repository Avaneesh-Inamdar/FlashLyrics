package com.lyricx.lyricx

import android.content.Context
import org.json.JSONObject

/**
 * Floating window layout chosen in Settings.
 *
 * - [showHeader]: title/artist row at the top of the window (default on).
 * - [tvMode]: lyrics only, larger text, placed at the bottom of the screen.
 *   TV mode always hides the header and the touch controls row.
 */
data class OverlayLayout(val showHeader: Boolean = true, val tvMode: Boolean = false) {
    val headerVisible get() = showHeader && !tvMode
    val controlsVisible get() = !tvMode
    val textScale get() = if (tvMode) TV_TEXT_SCALE else 1f

    companion object {
        const val TV_TEXT_SCALE = 1.25f

        fun fromSettingsJson(raw: String?): OverlayLayout {
            val settings = try { JSONObject(raw ?: "{}") } catch (_: Exception) { JSONObject() }
            return OverlayLayout(
                showHeader = settings.optBoolean("floatingOverlayShowHeader", true),
                tvMode = settings.optBoolean("floatingOverlayTvMode", false),
            )
        }

        fun read(context: Context): OverlayLayout = try {
            fromSettingsJson(context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.app_settings", null))
        } catch (_: Exception) { OverlayLayout() }
    }
}
