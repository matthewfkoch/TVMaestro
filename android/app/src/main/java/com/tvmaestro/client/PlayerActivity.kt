package com.tvmaestro.client

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.ui.PlayerView

class PlayerActivity : AppCompatActivity() {
    private lateinit var root: View
    private lateinit var grid: GridLayout
    private lateinit var idlePanel: LinearLayout
    private lateinit var addressValue: TextView
    private lateinit var addressHint: TextView
    private lateinit var deviceStatus: TextView
    private lateinit var deviceDetail: TextView
    private lateinit var playbackChrome: FrameLayout
    private lateinit var chromeMessage: TextView
    private lateinit var chromeSettings: Button
    private val players = mutableListOf<ExoPlayer>()
    private val views = mutableListOf<PlayerView>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val tag = "PlayerActivity"
    private var hideChrome: Runnable? = null

    private val sessionListener: (PlaybackSession?) -> Unit = { session ->
        runOnUiThread { applySession(session) }
    }

    private val guideListener: (Boolean) -> Unit = {
        runOnUiThread { refreshIdle() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_player)
        root = findViewById(R.id.root)
        grid = findViewById(R.id.playerGrid)
        idlePanel = findViewById(R.id.idlePanel)
        addressValue = findViewById(R.id.addressValue)
        addressHint = findViewById(R.id.addressHint)
        deviceStatus = findViewById(R.id.deviceStatus)
        deviceDetail = findViewById(R.id.deviceDetail)
        playbackChrome = findViewById(R.id.playbackChrome)
        chromeMessage = findViewById(R.id.chromeMessage)
        chromeSettings = findViewById(R.id.chromeSettingsButton)

        findViewById<Button>(R.id.settingsButton).setOnClickListener { openSettings() }
        chromeSettings.setOnClickListener { openSettings() }

        startControlService()
        SessionStore.addListener(sessionListener)
        GuideReach.addListener(guideListener)
        applySession(SessionStore.current)
        refreshIdle()
    }

    override fun onResume() {
        super.onResume()
        refreshIdle()
    }

    override fun onDestroy() {
        SessionStore.removeListener(sessionListener)
        GuideReach.removeListener(guideListener)
        hideChrome?.let { mainHandler.removeCallbacks(it) }
        mainHandler.removeCallbacksAndMessages(null)
        releasePlayers()
        super.onDestroy()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (!isPlaying || event.action != KeyEvent.ACTION_DOWN) {
            return super.dispatchKeyEvent(event)
        }
        when (event.keyCode) {
            KeyEvent.KEYCODE_BACK,
            KeyEvent.KEYCODE_ESCAPE,
            KeyEvent.KEYCODE_BUTTON_B,
            -> {
                stopPlayback()
                return true
            }
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_MEDIA_PLAY,
            KeyEvent.KEYCODE_MEDIA_PAUSE,
            -> {
                showChrome(focusSettings = true)
                return true
            }
            else -> {
                if (playbackChrome.visibility != View.VISIBLE) {
                    showChrome(focusSettings = true)
                    return true
                }
                scheduleChromeHide()
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun openSettings() {
        startActivity(Intent(this, SettingsActivity::class.java))
    }

    private fun startControlService() {
        val intent = Intent(this, ClientService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun refreshIdle() {
        val port = Prefs.port(this)
        val ip = ServerCec.localIpv4()
        if (ip == null) {
            addressValue.text = getString(R.string.no_lan)
            addressValue.setTextColor(getColor(R.color.warn))
            addressHint.visibility = View.GONE
        } else {
            addressValue.text = "$ip:$port"
            addressValue.setTextColor(getColor(R.color.text))
            addressHint.visibility = View.VISIBLE
        }
        val max = DecoderCapability.detect().multiviewMax
        val connected = GuideReach.connected
        deviceStatus.text = getString(if (connected) R.string.guide_connected else R.string.waiting)
        deviceStatus.setTextColor(getColor(if (connected) R.color.accent_on else R.color.text))
        deviceStatus.setBackgroundResource(if (connected) R.drawable.bg_pill_on else R.drawable.bg_chip)
        deviceDetail.text =
            if (max <= 1) {
                getString(R.string.streams_one)
            } else {
                getString(R.string.streams_many, max)
            }
    }

    private val isPlaying: Boolean
        get() = SessionStore.current?.slots?.any { it.isPlayable() } == true

    private fun stopPlayback() {
        SessionStore.set(null)
    }

    private fun showChrome(focusSettings: Boolean) {
        if (!isPlaying) return
        playbackChrome.visibility = View.VISIBLE
        if (focusSettings) chromeSettings.requestFocus()
        scheduleChromeHide()
    }

    private fun scheduleChromeHide() {
        hideChrome?.let { mainHandler.removeCallbacks(it) }
        val hide =
            Runnable {
                if (isPlaying) {
                    playbackChrome.visibility = View.GONE
                    chromeSettings.clearFocus()
                }
            }
        hideChrome = hide
        mainHandler.postDelayed(hide, 4_000)
    }

    private fun applySession(session: PlaybackSession?) {
        mainHandler.removeCallbacksAndMessages(null)
        hideChrome = null
        releasePlayers()
        val playing = session?.slots?.any { it.isPlayable() } == true
        root.keepScreenOn = playing
        if (!playing) {
            idlePanel.visibility = View.VISIBLE
            grid.visibility = View.GONE
            playbackChrome.visibility = View.GONE
            chromeMessage.visibility = View.GONE
            refreshIdle()
            findViewById<Button>(R.id.settingsButton).requestFocus()
            return
        }
        idlePanel.visibility = View.GONE
        grid.visibility = View.VISIBLE
        chromeMessage.text = ""
        chromeMessage.visibility = View.GONE
        showChrome(focusSettings = false)

        val layout = session?.layout ?: "1"
        val (rows, cols) = layoutDims(layout)
        grid.rowCount = rows
        grid.columnCount = cols

        val slots = session?.slots.orEmpty().take(rows * cols)
        val playableCount = slots.count { it.isPlayable() }
        val multi = playableCount > 1
        val hwIndex = slots.indexOfFirst { it.audio && it.isPlayable() }.let { if (it >= 0) it else slots.indexOfFirst { it.isPlayable() } }
        val gap = dp(8)
        slots.forEachIndexed { index, slot ->
            val row = index / cols
            val col = index % cols
            val cellParams =
                GridLayout.LayoutParams().apply {
                    width = 0
                    height = 0
                    rowSpec = GridLayout.spec(row, 1f)
                    columnSpec = GridLayout.spec(col, 1f)
                    setMargins(if (col == 0) 0 else gap, if (row == 0) 0 else gap, 0, 0)
                }
            val cell = FrameLayout(this).apply { layoutParams = cellParams }
            val rawUrl = slot.url
            if (rawUrl.isNullOrBlank()) {
                cell.setBackgroundColor(getColor(R.color.empty_pane))
                if (multi) addStroke(cell, audio = false)
                grid.addView(cell)
                return@forEachIndexed
            }
            val url = if (multi && index != hwIndex) lightenStreamUrl(rawUrl) else rawUrl
            val view =
                PlayerView(this).apply {
                    useController = false
                    layoutParams = FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT,
                    )
                }
            val preferSoftware = multi && index != hwIndex
            val player = buildPlayer(preferSoftware)
            player.volume = if (slot.audio) 1f else 0f
            val errorLabel = paneErrorLabel()
            player.addListener(
                object : Player.Listener {
                    override fun onPlayerError(error: PlaybackException) {
                        Log.e(tag, "pane $index error: ${error.message}", error)
                        errorLabel.visibility = View.VISIBLE
                        chromeMessage.text = "Pane ${index + 1}: ${error.message ?: getString(R.string.pane_failed)}"
                        chromeMessage.visibility = View.VISIBLE
                        showChrome(focusSettings = false)
                    }
                },
            )
            view.player = player
            cell.addView(view)
            cell.addView(errorLabel)
            if (multi) addStroke(cell, audio = slot.audio)
            grid.addView(cell)
            views.add(view)
            players.add(player)

            val delayMs = if (multi) index * 350L else 0L
            mainHandler.postDelayed({
                if (players.contains(player)) {
                    player.setMediaItem(MediaItem.fromUri(url))
                    player.playWhenReady = true
                    player.prepare()
                }
            }, delayMs)
        }
    }

    private fun addStroke(cell: FrameLayout, audio: Boolean) {
        val stroke =
            View(this).apply {
                background = getDrawable(if (audio) R.drawable.pane_stroke_audio else R.drawable.pane_stroke)
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                )
            }
        cell.addView(stroke)
    }

    private fun paneErrorLabel(): TextView =
        TextView(this).apply {
            text = getString(R.string.pane_failed)
            setTextColor(getColor(R.color.warn))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            gravity = Gravity.CENTER
            setBackgroundColor(0x73000000)
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
        }

    private fun buildPlayer(preferSoftware: Boolean): ExoPlayer {
        val renderersFactory =
            DefaultRenderersFactory(this).setEnableDecoderFallback(true)
        if (preferSoftware) {
            renderersFactory.setMediaCodecSelector(
                MediaCodecSelector { mimeType, requiresSecureDecoder, requiresTunnelingDecoder ->
                    val infos =
                        MediaCodecUtil.getDecoderInfos(
                            mimeType,
                            requiresSecureDecoder,
                            requiresTunnelingDecoder,
                        )
                    infos.sortedByDescending { it.softwareOnly }
                },
            )
        }
        return ExoPlayer.Builder(this, renderersFactory).build()
    }

    /**
     * Ask Channels DVR to transcode instead of codec=copy for secondary panes.
     * Still often 1080p, but pairs better with software decode / fallback.
     */
    private fun lightenStreamUrl(url: String): String {
        var out = url.replace("codec=copy", "codec=h264", ignoreCase = true)
        if (!out.contains("codec=", ignoreCase = true)) {
            out = if (out.contains("?")) "$out&codec=h264" else "$out?codec=h264"
        }
        return out
    }

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics,
        ).toInt()

    private fun releasePlayers() {
        views.forEach { it.player = null }
        players.forEach {
            try {
                it.stop()
                it.release()
            } catch (_: Exception) {
            }
        }
        players.clear()
        views.clear()
        grid.removeAllViews()
    }
}
