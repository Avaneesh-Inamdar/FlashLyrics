package com.lyricx.lyricx

import android.content.Context
import android.content.Intent
import android.os.Looper
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSettings

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class OverlayLayoutTest {
    private lateinit var context: Context
    private var controller: ServiceController<LyricsOverlayService>? = null
    private val plainLyrics = (1..12).joinToString("\n") { "Line $it of the song" }

    @Before fun setup() {
        context = RuntimeEnvironment.getApplication()
        ShadowSettings.setCanDrawOverlays(true)
        assertFalse(MainActivity.isAppInForeground)
        OverlayLyricsCache.update("", "", "", "", 0)
    }

    @After fun cleanup() {
        controller?.destroy()
        controller = null
    }

    private fun saveSettings(json: String?) {
        val editor = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
        if (json == null) editor.remove("flutter.app_settings") else editor.putString("flutter.app_settings", json)
        editor.commit()
    }

    private fun show(): LyricsOverlayService {
        val intent = Intent(context, LyricsOverlayService::class.java).apply {
            action = LyricsOverlayService.ACTION_SHOW
            putExtra("title", "The Fall")
            putExtra("artist", "Rhye")
            putExtra("lyrics", plainLyrics)
            putExtra("enableSeek", false)
        }
        val c = Robolectric.buildService(LyricsOverlayService::class.java, intent).create().startCommand(0, 1)
        controller = c
        shadowOf(Looper.getMainLooper()).idle()
        return c.get()
    }

    @Suppress("UNCHECKED_CAST")
    private fun <T> LyricsOverlayService.field(name: String): T =
        LyricsOverlayService::class.java.getDeclaredField(name).apply { isAccessible = true }.get(this) as T

    private fun View.shownInWindow(): Boolean {
        var v: View? = this
        while (v != null) {
            if (v.visibility != View.VISIBLE) return false
            v = v.parent as? View
        }
        return true
    }

    private fun drag(target: View, dx: Float, dy: Float) {
        val t = SystemClock.uptimeMillis()
        target.dispatchTouchEvent(MotionEvent.obtain(t, t, MotionEvent.ACTION_DOWN, 10f, 10f, 0))
        target.dispatchTouchEvent(MotionEvent.obtain(t, t + 16, MotionEvent.ACTION_MOVE, 10f + dx, 10f + dy, 0))
        target.dispatchTouchEvent(MotionEvent.obtain(t, t + 32, MotionEvent.ACTION_UP, 10f + dx, 10f + dy, 0))
    }

    private fun lyricTextSizes(service: LyricsOverlayService): List<Float> {
        val container = service.field<LinearLayout>("linesContainer")
        return (0 until container.childCount).mapNotNull { (container.getChildAt(it) as? TextView)?.textSize }
    }

    @Test fun parsesSettingsWithSafeDefaults() {
        assertEquals(OverlayLayout(showHeader = true, tvMode = false), OverlayLayout.fromSettingsJson(null))
        assertEquals(OverlayLayout(), OverlayLayout.fromSettingsJson("not json"))
        // Settings saved by 1.4.4 have neither key.
        assertEquals(OverlayLayout(), OverlayLayout.fromSettingsJson("{\"floatingOverlaySeekEnabled\":true}"))
        val compact = OverlayLayout.fromSettingsJson("{\"floatingOverlayShowHeader\":false}")
        assertFalse(compact.headerVisible)
        assertTrue(compact.controlsVisible)
        assertEquals(1f, compact.textScale)
        // TV mode wins over a "show title" preference.
        val tv = OverlayLayout.fromSettingsJson("{\"floatingOverlayShowHeader\":true,\"floatingOverlayTvMode\":true}")
        assertFalse(tv.headerVisible)
        assertFalse(tv.controlsVisible)
        assertEquals(OverlayLayout.TV_TEXT_SCALE, tv.textScale)
    }

    @Test fun defaultWindowIsUnchanged() {
        saveSettings(null)
        val service = show()
        assertTrue(LyricsOverlayService.isOverlayShowing)
        assertTrue(service.field<View>("headerRowView").shownInWindow())
        assertTrue(service.field<View>("dividerView").shownInWindow())
        assertTrue(service.field<View>("controlsRowView").shownInWindow())
        assertFalse(service.field<View>("compactCloseView").shownInWindow())
        assertEquals("The Fall", service.field<TextView>("titleView").text.toString())
        assertEquals("drag header to move", service.field<TextView>("hintView").text.toString())
        assertTrue(lyricTextSizes(service).all { it == 14f })

        // The lyrics area does not move the window when the header is available.
        val lp = service.field<WindowManager.LayoutParams>("layoutParams")
        val before = lp.x to lp.y
        drag(service.field<ScrollView>("lyricsScrollView"), 50f, 80f)
        assertEquals(before, lp.x to lp.y)
        // The header still does.
        drag(service.field<View>("headerRowView"), 50f, 80f)
        assertEquals(before.first + 50 to before.second + 80, lp.x to lp.y)
    }

    @Test fun hiddenTitleShowsOnlyLyricsAndControls() {
        saveSettings("{\"floatingOverlayShowHeader\":false}")
        val service = show()
        assertFalse(service.field<View>("headerRowView").shownInWindow())
        assertFalse(service.field<View>("dividerView").shownInWindow())
        assertTrue(service.field<View>("controlsRowView").shownInWindow())
        assertTrue(service.field<View>("compactCloseView").shownInWindow())
        assertEquals("drag to move", service.field<TextView>("hintView").text.toString())
        assertTrue(lyricTextSizes(service).all { it == 14f })

        // Without a header, the lyrics and the hint move the window.
        val lp = service.field<WindowManager.LayoutParams>("layoutParams")
        val start = lp.x to lp.y
        drag(service.field<ScrollView>("lyricsScrollView"), 50f, 80f)
        assertEquals(start.first + 50 to start.second + 80, lp.x to lp.y)
        drag(service.field<TextView>("hintView"), -20f, -30f)
        assertEquals(start.first + 30 to start.second + 50, lp.x to lp.y)

        // The relocated close button still closes the window.
        service.field<View>("compactCloseView").performClick()
        shadowOf(Looper.getMainLooper()).idle()
        assertFalse(LyricsOverlayService.isOverlayShowing)
    }

    @Test fun tvModeShowsLargerLyricsOnlyAtTheBottom() {
        saveSettings("{\"floatingOverlayTvMode\":true}")
        val service = show()
        assertFalse(service.field<View>("headerRowView").shownInWindow())
        assertFalse(service.field<View>("dividerView").shownInWindow())
        assertFalse(service.field<View>("controlsRowView").shownInWindow())
        assertTrue(service.field<View>("lyricsScrollView").shownInWindow())
        val sizes = lyricTextSizes(service)
        assertTrue(sizes.isNotEmpty())
        assertTrue(sizes.all { it == 14f * OverlayLayout.TV_TEXT_SCALE })

        val frame = service.field<View>("overlayView")
        val dm = context.resources.displayMetrics
        val lp = service.field<WindowManager.LayoutParams>("layoutParams")
        val margin = (32 * dm.density).toInt()
        fun relayout(w: Int, h: Int) {
            frame.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY))
            frame.layout(0, 0, w, h)
        }
        fun assertCentredAtBottom() {
            assertTrue(frame.width > 0 && frame.height > 0)
            val screen = android.graphics.Rect().also { frame.getWindowVisibleDisplayFrame(it) }
            assertTrue(screen.width() > 0 && screen.height() > 0)
            assertEquals(((screen.width() - frame.width) / 2).coerceAtLeast(0), lp.x)
            assertEquals((screen.height() - frame.height - margin).coerceAtLeast(0), lp.y)
        }

        // Once measured, the window is centred horizontally near the bottom edge.
        if (frame.width == 0) relayout(200, 150)
        assertCentredAtBottom()
        assertNotEquals(20 to 200, lp.x to lp.y) // not the default top-left spot

        // The window's width follows the lyrics; it stays centred when its size changes.
        relayout(240, 160)
        assertCentredAtBottom()
        relayout(180, 160)
        assertCentredAtBottom()

        // After the user moves it, TV mode leaves the position alone.
        drag(service.field<ScrollView>("lyricsScrollView"), -40f, -60f)
        val moved = lp.x to lp.y
        relayout(220, 150)
        assertEquals(moved, lp.x to lp.y)
    }

    @Test fun tvModeKeepsTapToSeekScrolling() {
        saveSettings("{\"floatingOverlayTvMode\":true}")
        val intent = Intent(context, LyricsOverlayService::class.java).apply {
            action = LyricsOverlayService.ACTION_SHOW
            putExtra("title", "Song")
            putExtra("artist", "Artist")
            putExtra("lrcLyrics", "[00:01.00]One\n[00:02.00]Two\n[00:03.00]Three")
            putExtra("enableSeek", true)
        }
        val c = Robolectric.buildService(LyricsOverlayService::class.java, intent).create().startCommand(0, 1)
        controller = c
        shadowOf(Looper.getMainLooper()).idle()
        val service = c.get()
        val lp = service.field<WindowManager.LayoutParams>("layoutParams")
        val before = lp.x to lp.y
        // With tap-to-seek on, touches on the lyrics scroll instead of moving the window.
        drag(service.field<ScrollView>("lyricsScrollView"), 50f, 80f)
        assertEquals(before, lp.x to lp.y)
    }
}
