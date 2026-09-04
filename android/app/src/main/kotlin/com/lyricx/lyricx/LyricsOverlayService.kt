package com.lyricx.lyricx

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.DisplayMetrics
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.app.NotificationCompat
import java.util.regex.Pattern

/**
 * Floating overlay service showing current lyrics over other apps.
 * Requires SYSTEM_ALERT_WINDOW permission.
 * Draggable, closable, updates via Intent extras.
 */
class LyricsOverlayService : Service() {

    companion object {
        private const val TAG = "LyricsOverlayService"
        const val ACTION_SHOW = "SHOW_OVERLAY"
        const val ACTION_HIDE = "HIDE_OVERLAY"
        const val ACTION_UPDATE = "UPDATE_LYRICS"
        private const val CHANNEL_ID = "flashlyrics_overlay"
        private const val NOTIF_ID = 1001
        private const val OVERLAY_UPDATE_INTERVAL_MS = 250L
        private const val SYNC_LEAD_MS = 800L
        // Static flag so MainActivity can check if overlay is currently showing
        @Volatile var isOverlayShowing: Boolean = false
            private set
        @Volatile var activeServiceInstance: LyricsOverlayService? = null
            private set

        fun onSongChanged(title: String, artist: String) {
            activeServiceInstance?.handleSongChanged(title, artist)
        }
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var isShowing = false

    private var titleView: TextView? = null
    private var artistViewRef: TextView? = null  // stored ref to artist TextView for live updates
    private var currentLineView: TextView? = null
    private var nextLineView: TextView? = null
    private var linesContainer: LinearLayout? = null
    private var lyricsScrollView: ScrollView? = null
    private var hintView: TextView? = null
    private var plainFallbackLines: List<String> = emptyList()

    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f

    // Resize state
    private var initialW = 0
    private var initialH = 0
    private var resizeInitialTouchX = 0f
    private var resizeInitialTouchY = 0f
    private var minWidthPx = 0
    private var maxWidthPx = 0
    private var minHeightPx = 0
    private var maxHeightPx = 0
    private var baseCurrentSp = 16f
    private var baseNextSp = 12f
    private var baseWidthPxForScale = 0

    // Skeleton loading state
    private var skeletonAnimator: android.animation.ValueAnimator? = null
    private var isShowingSkeleton = false

    // LRC data for realtime sync
    data class LrcLine(val ts: Long, val text: String)
    private var lrcLines: List<LrcLine> = emptyList()
    private var lrcOffsetMs: Long = 0
    private var syncOffsetMs: Long = 0

    // Track currently displayed song to detect changes via cache polling
    private var currentDisplayedTitle: String = ""
    private var currentDisplayedArtist: String = ""
    private var currentDisplayedLrcHash: Int = 0
    private var currentDisplayedPlainHash: Int = 0

    // Tap-to-seek & scrolling state
    private var isSeekEnabled: Boolean = false
    private var isUserScrolling: Boolean = false
    private var lastUserInteractionTime: Long = 0L
    private var autoScrollResumeRunnable: Runnable? = null
    private val autoScrollResumeDelayMs = 4000L // resume auto-scroll 4s after user interaction

    private val overlayHandler = Handler(Looper.getMainLooper())
    private var overlayRunnable: Runnable? = null
    private var lastDisplayedIdx = -2
    private var mediaSessionManager: MediaSessionManager? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        mediaSessionManager = getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
        val dm = resources.displayMetrics
        minWidthPx = (200 * dm.density).toInt()
        maxWidthPx = dm.widthPixels - (32 * dm.density).toInt()
        minHeightPx = (140 * dm.density).toInt()
        maxHeightPx = (dm.heightPixels * 0.72f).toInt()
        baseWidthPxForScale = (340 * dm.density).toInt()
        baseCurrentSp = 16f
        baseNextSp = 12f
        createNotificationChannel()
        activeServiceInstance = this
        Log.d(TAG, "Service created")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> {
                val title = intent.getStringExtra("title") ?: ""
                val artist = intent.getStringExtra("artist") ?: ""
                val currentLine = intent.getStringExtra("currentLine") ?: ""
                val lyrics = intent.getStringExtra("lyrics") ?: ""
                val lrc = intent.getStringExtra("lrcLyrics") ?: intent.getStringExtra("lrc") ?: ""
                val offset = intent.getIntExtra("syncOffsetMs", 0)
                val seekEnabled = intent.getBooleanExtra("enableSeek", OverlayLyricsCache.seekEnabled)
                val useLrc = if (lrc.isNotEmpty()) lrc else lyrics
                showOverlay(title, artist, currentLine, lyrics, useLrc, offset.toLong(), seekEnabled)
            }
            ACTION_UPDATE -> {
                // Legacy manual update from Flutter - keep for compatibility
                // Also allow updating LRC dynamically
                val lrc = intent.getStringExtra("lrcLyrics")
                if (!lrc.isNullOrEmpty()) {
                    parseLrc(lrc, syncOffsetMs)
                }
                val currentLine = intent.getStringExtra("currentLine") ?: ""
                val nextLine = intent.getStringExtra("nextLine") ?: ""
                if (currentLine.isNotEmpty() || nextLine.isNotEmpty()) {
                    // If we have LRC, let timer handle it; otherwise do manual update
                    if (lrcLines.isEmpty()) updateLyrics(currentLine, nextLine)
                }
                val off = intent.getIntExtra("syncOffsetMs", Int.MIN_VALUE)
                if (off != Int.MIN_VALUE) syncOffsetMs = off.toLong()
            }
            ACTION_HIDE -> {
                hideOverlay()
            }
            else -> {
                // Fallback: if started without action but has extras, show
                val title = intent?.getStringExtra("title")
                if (title != null) {
                    val artist = intent.getStringExtra("artist") ?: ""
                    val currentLine = intent.getStringExtra("currentLine") ?: ""
                    val lrc = intent.getStringExtra("lrcLyrics") ?: ""
                    val offset = intent.getIntExtra("syncOffsetMs", 0)
                    val seekEnabled = intent?.getBooleanExtra("enableSeek", OverlayLyricsCache.seekEnabled) ?: false
                    showOverlay(title, artist, currentLine, "", lrc, offset.toLong(), seekEnabled)
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Lyrics Overlay",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows floating lyrics"
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val hideIntent = Intent(this, LyricsOverlayService::class.java).apply { action = ACTION_HIDE }
        val pending = android.app.PendingIntent.getService(
            this, 0, hideIntent, android.app.PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("FlashLyrics overlay active")
            .setContentText("Tap to hide floating lyrics")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Hide", pending)
            .build()
    }

    fun handleSongChanged(title: String, artist: String) {
        overlayHandler.post {
            if (title.isNotEmpty() && (title != currentDisplayedTitle || artist != currentDisplayedArtist)) {
                Log.d(TAG, "Direct song change notification: $title by $artist (was $currentDisplayedTitle)")
                currentDisplayedTitle = title
                currentDisplayedArtist = artist
                currentDisplayedLrcHash = 0
                currentDisplayedPlainHash = 0
                lrcLines = emptyList()
                plainFallbackLines = emptyList()
                lastDisplayedIdx = -2
                updateTitle(title, artist)
                renderSkeletonLoading("Loading lyrics...")
            }
        }
    }

    private fun showOverlay(title: String, artist: String, currentLine: String, fullLyrics: String, lrcContent: String = "", lrcSyncOffset: Long = 0, enableSeek: Boolean = OverlayLyricsCache.seekEnabled) {
        if (!Settings.canDrawOverlays(this)) {
            Log.w(TAG, "No overlay permission, cannot show")
            stopSelf()
            return
        }
        // Parse LRC for realtime sync; if lrc empty, fallback to plain lines
        if (lrcContent.isNotEmpty() && isValidLrc(lrcContent)) {
            parseLrc(lrcContent, lrcSyncOffset)
        } else if (isValidLrc(fullLyrics)) {
            parseLrc(fullLyrics, lrcSyncOffset)
        } else {
            // Plain fallback
            lrcLines = emptyList()
            plainFallbackLines = fullLyrics.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
            syncOffsetMs = lrcSyncOffset
            // Ensure cached placeholder lines are rendered correctly (e.g., "Fetching...")
            if (currentLine.isNotEmpty() && plainFallbackLines.isEmpty()) {
                plainFallbackLines = listOf(currentLine)
            } else if (currentLine.isNotEmpty() && plainFallbackLines.isNotEmpty()) {
                // If we have both plain and currentLine placeholder (fetching), prefer showing placeholder until real lyrics arrive
                // But if plain is empty, we already set fallback to placeholder
            }
            // If fullLyrics empty but we have placeholder, keep it
            if (plainFallbackLines.isEmpty() && currentLine.isNotEmpty()) {
                plainFallbackLines = listOf(currentLine)
            }
        }
        if (lrcLines.isNotEmpty()) syncOffsetMs = lrcSyncOffset

        // Track displayed identity for cache polling
        currentDisplayedTitle = title
        currentDisplayedArtist = artist
        currentDisplayedLrcHash = lrcContent.hashCode()
        currentDisplayedPlainHash = fullLyrics.hashCode()

        // Update seek mode and cache
        val seekModeChanged = isSeekEnabled != enableSeek
        isSeekEnabled = enableSeek
        OverlayLyricsCache.seekEnabled = enableSeek
        // Also persist for notification handling
        try {
            getSharedPreferences("overlay_cache", Context.MODE_PRIVATE).edit().putBoolean("seekEnabled", enableSeek).apply()
        } catch (_: Exception) {}

        if (isShowing) {
            updateTitle(title, artist)
            // If seek mode toggled, we need to recreate scroll behavior or update scroll view visibility
            if (seekModeChanged) {
                try {
                    lyricsScrollView?.isVerticalScrollBarEnabled = isSeekEnabled
                    hintView?.text = if (isSeekEnabled) "↕ scroll • tap to seek • drag header to move" else "drag header to move"
                    // Force re-render to apply clickability change
                    overlayHandler.post { renderLrcLines(lastDisplayedIdx) }
                } catch (_: Exception) {}
            }
            // Reset user scrolling state when new song arrives
            isUserScrolling = false
            lastUserInteractionTime = 0L
            autoScrollResumeRunnable?.let { overlayHandler.removeCallbacks(it) }
            // If we have placeholder plain lines (fetching), render them immediately
            // Otherwise normal LRC sync will handle it
            // Restart sync timer with new data
            startRealtimeSync()
            // If we have no LRC and no multi-line plain lyrics, show skeleton loading
            if (lrcLines.isEmpty()) {
                if (plainFallbackLines.isEmpty() || plainFallbackLines.size <= 1) {
                    overlayHandler.post {
                        renderSkeletonLoading(if (currentLine.isNotEmpty()) currentLine else "Fetching lyrics...")
                    }
                }
            }
            return
        }
        try {
            val view = createOverlayView(title, artist, currentLine)
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else
                    @Suppress("DEPRECATION")
                    WindowManager.LayoutParams.TYPE_PHONE,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = 20
                y = 200
            }
            windowManager?.addView(view, params)
            overlayView = view
            layoutParams = params
            isShowing = true
            isOverlayShowing = true  // update static flag

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForeground(NOTIF_ID, buildNotification())
                }
            } catch (e: Exception) {
                Log.e(TAG, "startForeground failed", e)
            }
            Log.d(TAG, "Overlay shown: $title - $artist lrcLines=${lrcLines.size} offset=$syncOffsetMs")
            if (lrcLines.isEmpty() && (plainFallbackLines.isEmpty() || plainFallbackLines.size <= 1)) {
                overlayHandler.post {
                    renderSkeletonLoading(if (currentLine.isNotEmpty()) currentLine else "Fetching lyrics...")
                }
            }
            startRealtimeSync()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show overlay", e)
        }
    }

    private fun createOverlayView(title: String, artist: String, currentLine: String): View {
        val ctx = this
        val density = resources.displayMetrics.density

        // Outer FrameLayout to host content + resize handle
        val frame = FrameLayout(ctx).apply {
            background = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.RECTANGLE
                cornerRadius = 20 * density
                setColor(Color.parseColor("#E6121217"))
                setStroke((1 * density).toInt(), Color.parseColor("#33FFFFFF"))
            }
            elevation = 12 * density
        }

        // Inner content LinearLayout
        val root = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding((16 * density).toInt(), (12 * density).toInt(), (16 * density).toInt(), (14 * density).toInt())
        }

        // Header row: title/artist + close button — header is the drag handle
        val header = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            // Give header a touch feedback background when seek enabled
            setPadding((4 * density).toInt(), (2 * density).toInt(), (4 * density).toInt(), (2 * density).toInt())
        }

        val headerText = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }

        titleView = TextView(ctx).apply {
            text = if (title.isNotEmpty()) title else "FlashLyrics"
            setTextColor(Color.WHITE)
            textSize = 13f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }

        val artistView = TextView(ctx).apply {
            text = artist
            setTextColor(Color.parseColor("#B3B3C2"))
            textSize = 11f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            visibility = if (artist.isNotEmpty()) View.VISIBLE else View.GONE
        }
        artistViewRef = artistView  // store reference for live updates

        headerText.addView(titleView)
        headerText.addView(artistView)

        val closeBtn = TextView(ctx).apply {
            text = "✕"
            setTextColor(Color.parseColor("#8A8A9C"))
            textSize = 18f
            setPadding((8 * density).toInt(), (4 * density).toInt(), (4 * density).toInt(), (4 * density).toInt())
            setOnClickListener { hideOverlay() }
        }

        header.addView(headerText)
        header.addView(closeBtn)

        // Divider
        val divider = View(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (1 * density).toInt()).apply {
                topMargin = (8 * density).toInt()
                bottomMargin = (10 * density).toInt()
            }
            setBackgroundColor(Color.parseColor("#1FFFFFFF"))
        }

        // ScrollView for lyrics — enables scrolling when seekEnabled, otherwise acts as static container
        lyricsScrollView = ScrollView(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, (180 * density).toInt()).apply {
                // Height will be updated on resize; start 180dp
            }
            isVerticalScrollBarEnabled = isSeekEnabled
            // Hide scrollbar when not seekable to keep clean look
            overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS
            setBackgroundColor(Color.TRANSPARENT)
            // Intercept user scroll to pause auto-scroll
            setOnTouchListener { _, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                        if (isSeekEnabled) onUserScrollInteraction()
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        if (isSeekEnabled) onUserScrollInteraction()
                    }
                }
                // Return false to let ScrollView handle the scroll; if seek disabled, block scroll
                !isSeekEnabled
            }
        }

        // Lines container - holds all lyric TextViews (scrollable when seek enabled)
        linesContainer = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(0, (4 * density).toInt(), 0, (4 * density).toInt())
        }
        // Current lyric line placeholder - will be replaced by renderLrcLines
        currentLineView = TextView(ctx).apply {
            text = if (currentLine.isNotEmpty()) currentLine else "Waiting for lyrics..."
            setTextColor(Color.WHITE)
            textSize = 16f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            gravity = Gravity.CENTER
            maxLines = 3
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        // Next lyric line placeholder
        nextLineView = TextView(ctx).apply {
            text = ""
            setTextColor(Color.parseColor("#8A8AA0"))
            textSize = 12f
            gravity = Gravity.CENTER
            maxLines = 2
            ellipsize = android.text.TextUtils.TruncateAt.END
            visibility = View.GONE
            setPadding(0, (6 * density).toInt(), 0, 0)
        }
        linesContainer?.addView(currentLineView)
        linesContainer?.addView(nextLineView)

        lyricsScrollView?.addView(linesContainer)

        // Controls row: font size +/- and hint
        val controls = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, (8 * density).toInt(), 0, 0)
        }
        val btnMinus = TextView(ctx).apply {
            text = "−"
            setTextColor(Color.parseColor("#9A9AAC"))
            textSize = 14f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            gravity = Gravity.CENTER
            minWidth = (32 * density).toInt()
            setPadding((10 * density).toInt(), (4 * density).toInt(), (10 * density).toInt(), (4 * density).toInt())
            background = android.graphics.drawable.GradientDrawable().apply {
                cornerRadius = 8 * density
                setColor(Color.parseColor("#22FFFFFF"))
            }
            setOnClickListener {
                if (baseCurrentSp > 10) baseCurrentSp -= 1
                if (baseNextSp > 8) baseNextSp -= 1
                renderLrcLines(lastDisplayedIdx)
            }
        }
        val btnPlus = TextView(ctx).apply {
            text = "+"
            setTextColor(Color.parseColor("#9A9AAC"))
            textSize = 14f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            gravity = Gravity.CENTER
            minWidth = (32 * density).toInt()
            setPadding((10 * density).toInt(), (4 * density).toInt(), (10 * density).toInt(), (4 * density).toInt())
            background = android.graphics.drawable.GradientDrawable().apply {
                cornerRadius = 8 * density
                setColor(Color.parseColor("#22FFFFFF"))
            }
            setOnClickListener {
                if (baseCurrentSp < 24) baseCurrentSp += 1
                if (baseNextSp < 18) baseNextSp += 1
                renderLrcLines(lastDisplayedIdx)
            }
        }
        val hintText = if (isSeekEnabled) "↕ scroll • tap to seek • drag header to move" else "drag header to move"
        val hint = TextView(ctx).apply {
            text = hintText
            setTextColor(Color.parseColor("#55FFFFFF"))
            textSize = 9f
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        hintView = hint
        controls.addView(btnMinus)
        controls.addView(hint)
        controls.addView(btnPlus)

        root.addView(header)
        root.addView(divider)
        lyricsScrollView?.let { root.addView(it) }
        root.addView(controls)

        frame.addView(root, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT))

        // Resize handle at bottom-right corner
        val resizeHandle = TextView(ctx).apply {
            text = "◢"
            setTextColor(Color.parseColor("#66FFFFFF"))
            textSize = 14f
            gravity = Gravity.CENTER
            setPadding((6 * density).toInt(), (2 * density).toInt(), (6 * density).toInt(), (4 * density).toInt())
            layoutParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM or Gravity.END)
        }
        frame.addView(resizeHandle)

        // Drag handling on HEADER only (so lyrics area can scroll)
        header.setOnTouchListener(object : View.OnTouchListener {
            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = layoutParams?.x ?: 0
                        initialY = layoutParams?.y ?: 0
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (event.rawX - initialTouchX).toInt()
                        val dy = (event.rawY - initialTouchY).toInt()
                        layoutParams?.let { p ->
                            p.x = initialX + dx
                            p.y = initialY + dy
                            try { windowManager?.updateViewLayout(frame, p) } catch (_: Exception) {}
                        }
                        return true
                    }
                }
                return false
            }
        })

        // Also allow dragging via divider area for convenience
        divider.setOnTouchListener(object : View.OnTouchListener {
            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = layoutParams?.x ?: 0
                        initialY = layoutParams?.y ?: 0
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (event.rawX - initialTouchX).toInt()
                        val dy = (event.rawY - initialTouchY).toInt()
                        layoutParams?.let { p ->
                            p.x = initialX + dx
                            p.y = initialY + dy
                            try { windowManager?.updateViewLayout(frame, p) } catch (_: Exception) {}
                        }
                        return true
                    }
                }
                return false
            }
        })

        // Resize handling — also adjusts ScrollView height
        resizeHandle.setOnTouchListener(object : View.OnTouchListener {
            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        val lp = layoutParams
                        if (lp != null) {
                            initialW = if (lp.width > 0) lp.width else frame.width
                            initialH = if (lp.height > 0) lp.height else frame.height
                            if (initialW <= 0) initialW = (340 * density).toInt()
                            if (initialH <= 0) initialH = frame.height.takeIf { it > 0 } ?: (260 * density).toInt()
                        }
                        resizeInitialTouchX = event.rawX
                        resizeInitialTouchY = event.rawY
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - resizeInitialTouchX
                        val dy = event.rawY - resizeInitialTouchY
                        var newW = (initialW + dx).toInt().coerceIn(minWidthPx, maxWidthPx)
                        var newH = (initialH + dy).toInt().coerceIn(minHeightPx, maxHeightPx)
                        layoutParams?.let { p ->
                            p.width = newW
                            p.height = newH
                            try { windowManager?.updateViewLayout(frame, p) } catch (_: Exception) {}
                            // Adjust ScrollView height to fill available space
                            val nonLyricsH = (145 * density).toInt()
                            val newScrollH = (newH - nonLyricsH).coerceAtLeast((80 * density).toInt())
                            lyricsScrollView?.layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, newScrollH)
                            lyricsScrollView?.requestLayout()
                        }
                        overlayHandler.post {
                            if (isShowingSkeleton) {
                                renderSkeletonLoading()
                            } else {
                                renderLrcLines(lastDisplayedIdx)
                            }
                        }
                        return true
                    }
                }
                return false
            }
        })

        // Pinch-to-resize support via ScaleGestureDetector on frame (optional lightweight)
        // Set initial width; clamp max height to 70% of screen so controls never go off-screen
        val screenH = resources.displayMetrics.heightPixels
        val maxOverlayH = (screenH * 0.72f).toInt()
        frame.layoutParams = FrameLayout.LayoutParams((340 * density).toInt(), FrameLayout.LayoutParams.WRAP_CONTENT)
        // Enforce a max height via a custom measure override is complex; instead we set the
        // ScrollView height cap so that even at largest font size the controls stay visible.
        // The ScrollView already has a fixed height (180dp) that is only grown on manual resize,
        // so this is a safety net on the overall frame.
        frame.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            val curH = frame.height
            if (curH > maxOverlayH) {
                val sv = lyricsScrollView
                if (sv != null) {
                    val curSvH = sv.layoutParams?.height ?: -1
                    if (curSvH > 0) {
                        val diff = curH - maxOverlayH
                        val newSvH = (curSvH - diff).coerceAtLeast((80 * density).toInt())
                        sv.layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, newSvH)
                        sv.requestLayout()
                    }
                }
            }
        }

        return frame
    }

    private fun updateTitle(title: String, artist: String) {
        overlayHandler.post {
            try {
                titleView?.text = if (title.isNotEmpty()) title else "FlashLyrics"
                artistViewRef?.apply {
                    text = artist
                    visibility = if (artist.isNotEmpty()) View.VISIBLE else View.GONE
                }
            } catch (e: Exception) {
                Log.e(TAG, "updateTitle failed", e)
            }
        }
    }

    private fun updateLyrics(currentLine: String, nextLine: String) {
        try {
            if (currentLine.isNotEmpty()) {
                currentLineView?.text = currentLine
            }
            if (nextLine.isNotEmpty()) {
                nextLineView?.apply {
                    text = nextLine
                    visibility = View.VISIBLE
                }
            } else {
                nextLineView?.visibility = View.GONE
            }
        } catch (e: Exception) {
            Log.e(TAG, "updateLyrics failed", e)
        }
    }

    // --- LRC parsing and realtime sync ---

    private fun isValidLrc(text: String): Boolean {
        return Pattern.compile("\\[\\d{2}:\\d{2}\\.\\d{2,3}\\]").matcher(text).find()
    }

    private fun parseLrc(lrc: String, offsetMs: Long) {
        try {
            val timePat = Pattern.compile("\\[(\\d{2}):(\\d{2})\\.(\\d{2,3})\\]")
            val metaPat = Pattern.compile("\\[(ti|ar|al|au|offset|length|by):.+?\\]", Pattern.CASE_INSENSITIVE)
            val parsed = mutableListOf<LrcLine>()
            var offset: Long = 0
            for (raw in lrc.split("\n")) {
                val line = raw.trim()
                if (line.isEmpty()) continue
                if (metaPat.matcher(line).find()) {
                    if (line.lowercase().startsWith("[offset:")) {
                        val v = line.substringAfter(":").substringBefore("]").trim()
                        v.toLongOrNull()?.let { offset = it }
                    }
                    continue
                }
                val m = timePat.matcher(line)
                val times = mutableListOf<Long>()
                var lastEnd = -1
                while (m.find()) {
                    val min = m.group(1)?.toLongOrNull() ?: 0
                    val sec = m.group(2)?.toLongOrNull() ?: 0
                    val csRaw = m.group(3) ?: "0"
                    val cs = csRaw.padEnd(3, '0').take(3).toLongOrNull() ?: 0
                    val ts = min * 60000 + sec * 1000 + cs
                    times.add(ts)
                    lastEnd = m.end()
                }
                if (times.isNotEmpty() && lastEnd >= 0) {
                    val text = line.substring(lastEnd).trim()
                    for (ts in times) parsed.add(LrcLine(ts, text))
                }
            }
            parsed.sortBy { it.ts }
            lrcLines = parsed
            lrcOffsetMs = offset
            syncOffsetMs = offsetMs
            lastDisplayedIdx = -2
            Log.d(TAG, "Parsed LRC lines=${parsed.size} offset=$offset syncOffset=$offsetMs")
        } catch (e: Exception) {
            Log.e(TAG, "parseLrc failed", e)
            lrcLines = emptyList()
        }
    }

    private fun getVisibleLineCount(): Int {
        val density = resources.displayMetrics.density
        val lpH = layoutParams?.height ?: 0
        val viewH = overlayView?.height ?: 0
        val hPx = when {
            lpH > 0 && lpH != WindowManager.LayoutParams.WRAP_CONTENT -> lpH
            viewH > 0 -> viewH
            else -> (260 * density).toInt() // default wrap estimate
        }
        // Reserve ~90dp for header+divider+controls, rest for lyrics
        val available = (hPx - (90 * density)).toInt().coerceAtLeast((60 * density).toInt())
        val lineH = (32 * density).toInt() // approx per line with padding
        val count = (available / lineH).coerceIn(2, 9)
        // Prefer odd count for centered current line
        return if (count % 2 == 0) count + 1 else count
    }

    // Called when user touches ScrollView — pauses auto-scroll temporarily
    private fun onUserScrollInteraction() {
        if (!isSeekEnabled) return
        isUserScrolling = true
        lastUserInteractionTime = SystemClock.elapsedRealtime()
        autoScrollResumeRunnable?.let { overlayHandler.removeCallbacks(it) }
        autoScrollResumeRunnable = Runnable {
            isUserScrolling = false
            Log.d(TAG, "Auto-scroll resumed after user idle")
            // Immediately snap back to current line after resume
            overlayHandler.post { scrollToCurrentLine(lastDisplayedIdx) }
        }
        overlayHandler.postDelayed(autoScrollResumeRunnable!!, autoScrollResumeDelayMs)
    }

    private fun seekToLyricPosition(positionMs: Long, targetIdx: Int = -1) {
        try {
            val msm = mediaSessionManager
            if (msm == null) {
                Log.w(TAG, "seek: no MediaSessionManager")
                return
            }
            val cn = ComponentName(this, MediaNotificationListener::class.java)
            val controllers = msm.getActiveSessions(cn)
            if (controllers.isNullOrEmpty()) {
                Log.w(TAG, "seek: no active sessions")
                return
            }
            var best: MediaController? = null
            var bestPlaying = false
            for (c in controllers) {
                val isPlaying = c.playbackState?.state == PlaybackState.STATE_PLAYING
                if (isPlaying && !bestPlaying) { best = c; bestPlaying = true }
                else if (best == null) { best = c; bestPlaying = isPlaying }
            }
            val controller = best ?: controllers[0]
            controller.transportControls.seekTo(positionMs)
            Log.d(TAG, "Seek to $positionMs ms via ${controller.packageName} targetIdx=$targetIdx")
            // No Toast — silent seek so the floating window stays unobstructed

            // If we know target index, immediately highlight and scroll to it (forced)
            if (targetIdx >= 0) {
                overlayHandler.post {
                    // Optimistically set current index to tapped line and re-render
                    lastDisplayedIdx = targetIdx
                    renderLrcLines(targetIdx)
                    // Force scroll even though isUserScrolling will be set
                    scrollToCurrentLine(targetIdx, force = true)
                }
            }

            // Pause auto-scroll briefly so seeking isn't immediately overridden,
            // but allow the forced scroll above to complete first
            overlayHandler.postDelayed({ onUserScrollInteraction() }, 150)

            // Also verify after a short time that actual position matches and correct if needed
            overlayHandler.postDelayed({
                val newPos = getCurrentPlaybackPositionMs()
                val idx = findCurrentIndex(newPos + lrcOffsetMs + syncOffsetMs + SYNC_LEAD_MS)
                if (idx != lastDisplayedIdx && idx >= 0) {
                    lastDisplayedIdx = idx
                    renderLrcLines(idx)
                    // After verification, ensure we're still at correct line (force if mismatch)
                    if (idx != targetIdx) scrollToCurrentLine(idx, force = false)
                }
            }, 600)
        } catch (e: Exception) {
            Log.e(TAG, "seek failed", e)
        }
    }

    private fun formatMs(ms: Long): String {
        val s = (ms / 1000).toInt()
        val m = s / 60
        val sec = s % 60
        return String.format("%d:%02d", m, sec)
    }

    private fun smoothScrollToPosition(scrollView: ScrollView, targetView: View) {
        scrollView.post {
            val y = targetView.top
            val viewHeight = scrollView.height
            val targetHeight = targetView.height
            // Center the target line in viewport
            val scrollY = (y - viewHeight / 2 + targetHeight / 2).coerceAtLeast(0)
            scrollView.smoothScrollTo(0, scrollY)
        }
    }

    private fun scrollToCurrentLine(centerIdx: Int, force: Boolean = false) {
        if (!isSeekEnabled && !force) return
        if (!force && isUserScrolling) {
            val elapsed = SystemClock.elapsedRealtime() - lastUserInteractionTime
            if (elapsed < autoScrollResumeDelayMs) return
            isUserScrolling = false
        }
        val sv = lyricsScrollView ?: return
        val container = linesContainer ?: return
        if (centerIdx < 0 || centerIdx >= container.childCount) return
        val target = container.getChildAt(centerIdx) ?: return
        smoothScrollToPosition(sv, target)
    }

    private fun renderSkeletonLoading(statusText: String = "Fetching lyrics...") {
        val container = linesContainer ?: return
        val scrollView = lyricsScrollView
        val density = resources.displayMetrics.density

        isShowingSkeleton = true
        lastDisplayedIdx = -2
        skeletonAnimator?.cancel()

        container.post {
            container.removeAllViews()

            val skeletonBox = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(0, (12 * density).toInt(), 0, (12 * density).toInt())
                layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            }

            val widthsFraction = listOf(0.75f, 0.50f, 0.85f, 0.60f)
            val barViews = mutableListOf<View>()

            val availableW = (layoutParams?.width?.takeIf { it > 0 } ?: (340 * density).toInt()) - (48 * density).toInt()

            for (frac in widthsFraction) {
                val barW = (availableW * frac).toInt().coerceAtLeast((80 * density).toInt())
                val bar = View(this).apply {
                    layoutParams = LinearLayout.LayoutParams(barW, (12 * density).toInt()).apply {
                        setMargins(0, (5 * density).toInt(), 0, (5 * density).toInt())
                    }
                    background = android.graphics.drawable.GradientDrawable().apply {
                        shape = android.graphics.drawable.GradientDrawable.RECTANGLE
                        cornerRadius = 6 * density
                        setColor(Color.parseColor("#26FFFFFF"))
                    }
                }
                skeletonBox.addView(bar)
                barViews.add(bar)
            }

            val statusView = TextView(this).apply {
                text = statusText
                setTextColor(Color.parseColor("#7A7A90"))
                textSize = 11f
                gravity = Gravity.CENTER
                setPadding(0, (8 * density).toInt(), 0, 0)
            }
            skeletonBox.addView(statusView)

            container.addView(skeletonBox)

            skeletonAnimator = android.animation.ValueAnimator.ofFloat(0.25f, 0.75f).apply {
                duration = 800L
                repeatMode = android.animation.ValueAnimator.REVERSE
                repeatCount = android.animation.ValueAnimator.INFINITE
                addUpdateListener { anim ->
                    val alphaVal = anim.animatedValue as Float
                    for (v in barViews) {
                        v.alpha = alphaVal
                    }
                }
                start()
            }

            scrollView?.post { scrollView.scrollTo(0, 0) }
        }
    }

    private fun renderLrcLines(centerIdx: Int) {
        val container = linesContainer ?: return
        val scrollView = lyricsScrollView
        val density = resources.displayMetrics.density
        // Run on UI thread
        container.post {
            skeletonAnimator?.cancel()
            isShowingSkeleton = false
            container.removeAllViews()
            if (lrcLines.isEmpty()) {
                // Plain fallback — when seek enabled, show all lines scrollable; otherwise windowed
                if (isSeekEnabled) {
                    // Show all plain lines
                    if (plainFallbackLines.isEmpty()) {
                        val tv = TextView(this).apply {
                            text = "No synced lyrics"
                            setTextColor(Color.WHITE)
                            textSize = baseCurrentSp
                            gravity = Gravity.CENTER
                            setPadding(0, (12 * density).toInt(), 0, (12 * density).toInt())
                        }
                        container.addView(tv)
                    } else {
                        for ((idx, line) in plainFallbackLines.withIndex()) {
                            val tv = TextView(this).apply {
                                text = line
                                setTextColor(Color.WHITE)
                                textSize = 13f
                                gravity = Gravity.CENTER
                                setPadding(0, (6*density).toInt(), 0, (6*density).toInt())
                                // Plain lines not seekable (no timestamp) — but allow scrolling
                                alpha = 0.95f
                            }
                            container.addView(tv)
                        }
                    }
                    // Ensure scroll view is scrollable when content exceeds viewport
                    scrollView?.isVerticalScrollBarEnabled = plainFallbackLines.size > 4
                    // For plain, keep at top (no auto-scroll)
                    scrollView?.post { scrollView.smoothScrollTo(0, 0) }
                } else {
                    // Windowed plain (original behavior)
                    val count = getVisibleLineCount()
                    val toShow = plainFallbackLines.take(count)
                    if (toShow.isEmpty()) {
                        val tv = TextView(this).apply {
                            text = "No synced lyrics"
                            setTextColor(Color.WHITE)
                            textSize = baseCurrentSp
                            gravity = Gravity.CENTER
                        }
                        container.addView(tv)
                    } else {
                        for (line in toShow) {
                            val tv = TextView(this).apply {
                                text = line
                                setTextColor(Color.WHITE)
                                textSize = 14f
                                gravity = Gravity.CENTER
                                setPadding(0, (4*density).toInt(), 0, (4*density).toInt())
                            }
                            container.addView(tv)
                        }
                    }
                    scrollView?.post { scrollView.scrollTo(0, 0) }
                }
                if (container.childCount > 0) currentLineView = container.getChildAt(0) as? TextView
                return@post
            }
            if (centerIdx < 0) {
                renderSkeletonLoading("Loading lyrics...")
                return@post
            }

            // Choose rendering mode based on seek toggle
            if (isSeekEnabled) {
                // Full scrollable list — render ALL lines, highlight current, make each tappable
                val curW = layoutParams?.width?.takeIf { it>0 && it != WindowManager.LayoutParams.WRAP_CONTENT } ?: overlayView?.width ?: baseWidthPxForScale
                val ratio = (curW.toFloat() / baseWidthPxForScale.toFloat()).coerceIn(0.75f, 1.6f)
                for (i in lrcLines.indices) {
                    val isCurrent = i == centerIdx
                    val tv = TextView(this).apply {
                        text = lrcLines[i].text
                        setTextColor(if (isCurrent) Color.WHITE else Color.parseColor("#B0B0C0"))
                        textSize = if (isCurrent) (baseCurrentSp * ratio).coerceIn(11f, 26f) else (baseNextSp * ratio).coerceIn(9f, 18f)
                        if (isCurrent) typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                        gravity = Gravity.CENTER
                        maxLines = 2
                        ellipsize = android.text.TextUtils.TruncateAt.END
                        setPadding(0, (4*density).toInt(), 0, (4*density).toInt())
                        // Highlight current more, fade distant
                        alpha = if (isCurrent) 1f else (0.78f - (kotlin.math.abs(i - centerIdx) * 0.06f).coerceIn(0f, 0.33f))
                        // Visual cue for tappability: subtle background on tap, add ripple via foreground?
                        isClickable = true
                        isFocusable = false
                        // Add slight background when seek enabled to hint tappability
                        if (!isCurrent) {
                            // Keep transparent but show press state via alpha
                        }
                        setOnClickListener {
                            val ts = lrcLines[i].ts
                            seekToLyricPosition(ts, i)
                        }
                        // Long press could show timestamp? optional
                    }
                    container.addView(tv)
                    if (isCurrent) {
                        currentLineView = tv
                        // Style current line with subtle background to indicate selection
                        tv.background = android.graphics.drawable.GradientDrawable().apply {
                            shape = android.graphics.drawable.GradientDrawable.RECTANGLE
                            cornerRadius = 8 * density
                            setColor(Color.parseColor("#1AFFFFFF"))
                        }
                        tv.setPadding((8*density).toInt(), (4*density).toInt(), (8*density).toInt(), (4*density).toInt())
                    }
                }
                // Auto-scroll to current line unless user is interacting
                if (!isUserScrolling) {
                    scrollToCurrentLine(centerIdx)
                }
            } else {
                // Windowed mode (original) — show only visibleCount lines centered
                val visibleCount = getVisibleLineCount()
                val half = visibleCount / 2
                var start = (centerIdx - half).coerceAtLeast(0)
                var end = (start + visibleCount - 1).coerceAtMost(lrcLines.size - 1)
                start = (end - visibleCount + 1).coerceAtLeast(0)
                val curW = layoutParams?.width?.takeIf { it>0 && it != WindowManager.LayoutParams.WRAP_CONTENT } ?: overlayView?.width ?: baseWidthPxForScale
                val ratio = (curW.toFloat() / baseWidthPxForScale.toFloat()).coerceIn(0.75f, 1.6f)
                for (i in start..end) {
                    val isCurrent = i == centerIdx
                    val tv = TextView(this).apply {
                        text = lrcLines[i].text
                        setTextColor(if (isCurrent) Color.WHITE else Color.parseColor("#B0B0C0"))
                        textSize = if (isCurrent) (baseCurrentSp * ratio).coerceIn(11f, 26f) else (baseNextSp * ratio).coerceIn(9f, 18f)
                        if (isCurrent) typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                        gravity = Gravity.CENTER
                        maxLines = 2
                        ellipsize = android.text.TextUtils.TruncateAt.END
                        setPadding(0, (3*density).toInt(), 0, (3*density).toInt())
                        alpha = if (isCurrent) 1f else 0.72f - (kotlin.math.abs(i - centerIdx) * 0.12f).coerceAtLeast(0.45f)
                        // Non-seekable mode: not clickable
                        isClickable = false
                    }
                    container.addView(tv)
                    if (isCurrent) currentLineView = tv
                }
                // In non-seekable mode, ensure scroll is at top (windowed content fits)
                scrollView?.post { scrollView.scrollTo(0, 0) }
            }
        }
    }

    private fun startRealtimeSync() {
        stopRealtimeSync()
        if (lrcLines.isEmpty()) {
            // Plain fallback: render immediately and keep polling cache for song changes
            overlayHandler.post { renderLrcLines(-1) }
            // Still start timer to poll for cache updates (song changed while showing placeholder)
            overlayRunnable = object : Runnable {
                override fun run() {
                    if (!isShowing) return
                    try {
                        // Check if cache has new song/lyrics
                        checkForCacheUpdate()
                        // If LRC became available after cache update, restart as LRC sync
                        if (lrcLines.isNotEmpty()) {
                            // LRC now available — restart full sync
                            stopRealtimeSync()
                            startRealtimeSync()
                            return
                        }
                        // For plain mode, re-render periodically in case window resized or cache changed without LRC
                        // Only re-render if we haven't just rendered
                        // No index tracking needed for plain, but keep polling
                    } catch (e: Exception) {
                        Log.e(TAG, "overlay plain poll error", e)
                    }
                    overlayHandler.postDelayed(this, OVERLAY_UPDATE_INTERVAL_MS)
                }
            }
            overlayHandler.postDelayed(overlayRunnable!!, OVERLAY_UPDATE_INTERVAL_MS)
            Log.d(TAG, "Plain fallback sync started, polling cache")
            return
        }
        // Initial render
        overlayHandler.post {
            val posMs = getCurrentPlaybackPositionMs()
            val idx = findCurrentIndex(posMs + lrcOffsetMs + syncOffsetMs + SYNC_LEAD_MS)
            lastDisplayedIdx = idx
            renderLrcLines(idx)
        }
        overlayRunnable = object : Runnable {
            override fun run() {
                if (!isShowing) return
                try {
                    // Poll cache for song change before computing index
                    checkForCacheUpdate()
                    // If cache update switched us to plain mode, restart as plain
                    if (lrcLines.isEmpty()) {
                        stopRealtimeSync()
                        startRealtimeSync()
                        return
                    }
                    val posMs = getCurrentPlaybackPositionMs()
                    val adjusted = posMs + lrcOffsetMs + syncOffsetMs + SYNC_LEAD_MS
                    val idx = findCurrentIndex(adjusted)
                    if (idx != lastDisplayedIdx) {
                        lastDisplayedIdx = idx
                        renderLrcLines(idx)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "overlay sync error", e)
                }
                overlayHandler.postDelayed(this, OVERLAY_UPDATE_INTERVAL_MS)
            }
        }
        overlayHandler.postDelayed(overlayRunnable!!, OVERLAY_UPDATE_INTERVAL_MS)
        Log.d(TAG, "Realtime sync started lines=${lrcLines.size}")
    }

    /**
     * Poll OverlayLyricsCache for song/lyrics changes.
     * This is a safety net in case Flutter's MethodChannel push missed
     * (e.g., app was backgrounded). If cache title/artist/lrc differs from
     * currently displayed, reload and re-render.
     */
    private fun checkForCacheUpdate() {
        try {
            // Immediate song change detection from active playback (e.g. track changed in music player)
            val nlsTitle = MediaNotificationListener.currentTitle
            val nlsArtist = MediaNotificationListener.currentArtist ?: ""
            if (!nlsTitle.isNullOrEmpty() && (nlsTitle != currentDisplayedTitle || (nlsArtist.isNotEmpty() && nlsArtist != currentDisplayedArtist))) {
                if (!OverlayLyricsCache.matches(nlsTitle, nlsArtist)) {
                    // Song changed in player, but new lyrics haven't arrived in cache yet!
                    currentDisplayedTitle = nlsTitle
                    currentDisplayedArtist = nlsArtist
                    currentDisplayedLrcHash = 0
                    currentDisplayedPlainHash = 0
                    lrcLines = emptyList()
                    plainFallbackLines = emptyList()
                    lastDisplayedIdx = -2
                    overlayHandler.post {
                        updateTitle(nlsTitle, nlsArtist)
                        renderSkeletonLoading("Loading lyrics...")
                    }
                    return
                }
            }

            val cacheTitle = OverlayLyricsCache.title
            val cacheArtist = OverlayLyricsCache.artist
            if (cacheTitle.isEmpty() && cacheArtist.isEmpty()) return
            val cacheLrc = OverlayLyricsCache.lrc
            val cachePlain = OverlayLyricsCache.plain
            val cacheOffset = OverlayLyricsCache.syncOffsetMs.toLong()
            val cacheSeek = OverlayLyricsCache.seekEnabled
            val cacheLrcHash = cacheLrc.hashCode()
            val cachePlainHash = cachePlain.hashCode()

            val titleChanged = cacheTitle != currentDisplayedTitle || cacheArtist != currentDisplayedArtist
            val lrcChanged = cacheLrcHash != currentDisplayedLrcHash
            val plainChanged = cachePlainHash != currentDisplayedPlainHash
            val offsetChanged = cacheOffset != syncOffsetMs
            val seekChanged = cacheSeek != isSeekEnabled

            if (!titleChanged && !lrcChanged && !plainChanged && !offsetChanged && !seekChanged) return

            Log.d(TAG, "Cache poll detected change: titleChanged=$titleChanged lrcChanged=$lrcChanged seekChanged=$seekChanged offset $syncOffsetMs -> $cacheOffset for $cacheTitle by $cacheArtist")
            // Update displayed tracking
            currentDisplayedTitle = cacheTitle
            currentDisplayedArtist = cacheArtist
            currentDisplayedLrcHash = cacheLrcHash
            currentDisplayedPlainHash = cachePlainHash
            // Sync seek mode if changed via cache
            if (seekChanged) {
                isSeekEnabled = cacheSeek
                overlayHandler.post {
                    lyricsScrollView?.isVerticalScrollBarEnabled = isSeekEnabled
                    hintView?.text = if (isSeekEnabled) "↕ scroll • tap to seek • drag header to move" else "drag header to move"
                    renderLrcLines(lastDisplayedIdx)
                }
            }

            // Update title view
            overlayHandler.post { updateTitle(cacheTitle, cacheArtist) }

            // Re-parse LRC or plain
            if (cacheLrc.isNotEmpty() && isValidLrc(cacheLrc)) {
                parseLrc(cacheLrc, cacheOffset)
            } else if (cachePlain.isNotEmpty() && isValidLrc(cachePlain)) {
                parseLrc(cachePlain, cacheOffset)
            } else {
                lrcLines = emptyList()
                plainFallbackLines = if (cachePlain.isNotEmpty()) {
                    cachePlain.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
                } else if (cacheLrc.isNotEmpty()) {
                    cacheLrc.split("\n").map { it.trim() }.filter { it.isNotEmpty() && !it.startsWith("[") }
                } else {
                    emptyList()
                }
                syncOffsetMs = cacheOffset
                lastDisplayedIdx = -2
                if (plainFallbackLines.isEmpty()) {
                    overlayHandler.post { renderSkeletonLoading("Fetching lyrics...") }
                } else {
                    overlayHandler.post { renderLrcLines(-1) }
                }
                return
            }
            syncOffsetMs = cacheOffset
            lastDisplayedIdx = -2
            // Will be rendered on next tick
            overlayHandler.post {
                val posMs = getCurrentPlaybackPositionMs()
                val idx = findCurrentIndex(posMs + lrcOffsetMs + syncOffsetMs + SYNC_LEAD_MS)
                lastDisplayedIdx = idx
                renderLrcLines(idx)
            }
        } catch (e: Exception) {
            Log.e(TAG, "checkForCacheUpdate failed", e)
        }
    }

    private fun stopRealtimeSync() {
        overlayRunnable?.let { overlayHandler.removeCallbacks(it) }
        overlayRunnable = null
        lastDisplayedIdx = -2
        autoScrollResumeRunnable?.let { overlayHandler.removeCallbacks(it) }
        // Don't clear isUserScrolling here — keep until explicit reset or timeout
    }

    private fun getCurrentPlaybackPositionMs(): Long {
        // Try MediaNotificationListener static extrapolated position first (fast)
        try {
            // If NLS has recent data, use it - it already extrapolates
            val nlsPos = MediaNotificationListener.currentPosition
            val nlsPlaying = MediaNotificationListener.currentIsPlaying
            // If NLS is playing and pos looks fresh (recent update within 2s), use it
            // We don't have last update time, so fallback to direct query if stale
            // Prefer direct query for accuracy
        } catch (_: Exception) {}
        // Direct MediaSessionManager query with extrapolation
        return queryPositionDirect()
    }

    private fun queryPositionDirect(): Long {
        return try {
            val msm = mediaSessionManager ?: return MediaNotificationListener.currentPosition
            val cn = ComponentName(this, MediaNotificationListener::class.java)
            val controllers = msm.getActiveSessions(cn)
            if (controllers.isNullOrEmpty()) return MediaNotificationListener.currentPosition
            // Prefer playing controller
            var best: MediaController? = null
            var bestPlaying = false
            for (c in controllers) {
                val isPlaying = c.playbackState?.state == PlaybackState.STATE_PLAYING
                if (isPlaying && !bestPlaying) { best = c; bestPlaying = true }
                else if (best == null) { best = c; bestPlaying = isPlaying }
            }
            best ?: return MediaNotificationListener.currentPosition
            val state = best.playbackState ?: return MediaNotificationListener.currentPosition
            val isPlaying = state.state == PlaybackState.STATE_PLAYING
            if (!isPlaying) return state.position
            val base = state.position
            val last = state.lastPositionUpdateTime
            val speed = if (state.playbackSpeed <= 0) 1.0f else state.playbackSpeed
            val elapsed = SystemClock.elapsedRealtime() - last
            val extrapolated = base + (elapsed * speed).toLong()
            val dur = best.metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: MediaNotificationListener.currentDuration
            when {
                extrapolated < 0 -> 0
                dur > 0 && extrapolated > dur -> dur
                else -> extrapolated
            }
        } catch (e: Exception) {
            MediaNotificationListener.currentPosition
        }
    }

    private fun findCurrentIndex(posMs: Long): Int {
        if (lrcLines.isEmpty()) return -1
        var idx = -1
        for (i in lrcLines.indices) {
            if (lrcLines[i].ts <= posMs) idx = i else break
        }
        return idx
    }

    private fun hideOverlay() {
        stopRealtimeSync()
        skeletonAnimator?.cancel()
        skeletonAnimator = null
        isShowingSkeleton = false
        try {
            overlayView?.let { v ->
                try { windowManager?.removeView(v) } catch (e: Exception) { Log.w(TAG, "removeView failed", e) }
            }
        } finally {
            overlayView = null
            layoutParams = null
            isShowing = false
            isOverlayShowing = false  // update static flag
            lrcLines = emptyList()
            plainFallbackLines = emptyList()
            currentDisplayedTitle = ""
            currentDisplayedArtist = ""
            currentDisplayedLrcHash = 0
            currentDisplayedPlainHash = 0
            isUserScrolling = false
            lastUserInteractionTime = 0L
            autoScrollResumeRunnable?.let { overlayHandler.removeCallbacks(it) }
            autoScrollResumeRunnable = null
            hintView = null
            lyricsScrollView = null
            linesContainer = null
            currentLineView = null
            nextLineView = null
            artistViewRef = null
            // Keep isSeekEnabled cached for next show, don't reset
            try { stopForeground(STOP_FOREGROUND_REMOVE) } catch (_: Exception) {}
            stopSelf()
            Log.d(TAG, "Overlay hidden")
        }
    }

    override fun onDestroy() {
        if (activeServiceInstance === this) activeServiceInstance = null
        stopRealtimeSync()
        hideOverlayViewOnly()
        super.onDestroy()
    }

    private fun hideOverlayViewOnly() {
        stopRealtimeSync()
        skeletonAnimator?.cancel()
        skeletonAnimator = null
        isShowingSkeleton = false
        try {
            overlayView?.let { v ->
                try { windowManager?.removeViewImmediate(v) } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
        overlayView = null
        isShowing = false
    }
}
