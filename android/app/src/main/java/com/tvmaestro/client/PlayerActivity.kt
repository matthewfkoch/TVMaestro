package com.tvmaestro.client

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.widget.Button
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
    private lateinit var grid: GridLayout
    private lateinit var idlePanel: LinearLayout
    private lateinit var statusText: TextView
    private val players = mutableListOf<ExoPlayer>()
    private val views = mutableListOf<PlayerView>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val tag = "PlayerActivity"

    private val sessionListener: (PlaybackSession?) -> Unit = { session ->
        runOnUiThread { applySession(session) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_player)
        grid = findViewById(R.id.playerGrid)
        idlePanel = findViewById(R.id.idlePanel)
        statusText = findViewById(R.id.statusText)
        findViewById<Button>(R.id.settingsButton).setOnClickListener {
            startActivity(Intent(this, SettingsActivity::class.java))
        }

        startControlService()
        SessionStore.addListener(sessionListener)
        applySession(SessionStore.current)
        statusText.text = "Control API on port ${Prefs.port(this)}. ${getString(R.string.waiting)}"
    }

    override fun onDestroy() {
        SessionStore.removeListener(sessionListener)
        mainHandler.removeCallbacksAndMessages(null)
        releasePlayers()
        super.onDestroy()
    }

    private fun startControlService() {
        val intent = Intent(this, ClientService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun applySession(session: PlaybackSession?) {
        mainHandler.removeCallbacksAndMessages(null)
        releasePlayers()
        if (session == null || session.slots.isEmpty()) {
            idlePanel.visibility = View.VISIBLE
            grid.visibility = View.GONE
            return
        }
        idlePanel.visibility = View.GONE
        grid.visibility = View.VISIBLE

        val layout = session.layout ?: "1"
        val (rows, cols) = layoutDims(layout)
        grid.rowCount = rows
        grid.columnCount = cols

        val slots = session.slots.take(rows * cols)
        val multi = slots.size > 1
        // Audio-focus pane keeps hardware decode; others prefer software to avoid
        // Amlogic/onn "NO_MEMORY" when opening multiple 1080p HW decoders.
        val hwIndex = slots.indexOfFirst { it.audio }.let { if (it >= 0) it else 0 }

        slots.forEachIndexed { index, slot ->
            val row = index / cols
            val col = index % cols
            val cellParams =
                GridLayout.LayoutParams().apply {
                    width = 0
                    height = 0
                    rowSpec = GridLayout.spec(row, 1f)
                    columnSpec = GridLayout.spec(col, 1f)
                    setMargins(1, 1, 1, 1)
                }
            val rawUrl = slot.url
            if (rawUrl.isNullOrBlank()) {
                // Empty composer slot — reserve the grid cell.
                grid.addView(View(this).apply { layoutParams = cellParams })
                return@forEachIndexed
            }
            val url = if (multi && index != hwIndex) lightenStreamUrl(rawUrl) else rawUrl
            val view =
                PlayerView(this).apply {
                    useController = false
                    layoutParams = cellParams
                }
            val preferSoftware = multi && index != hwIndex
            val player = buildPlayer(preferSoftware)
            player.volume = if (slot.audio) 1f else 0f
            player.addListener(
                object : Player.Listener {
                    override fun onPlayerError(error: PlaybackException) {
                        Log.e(tag, "pane $index error: ${error.message}", error)
                        statusText.text = "Pane ${index + 1}: ${error.message ?: "playback error"}"
                        // Keep other panes visible — do not tear down the whole grid.
                    }
                },
            )
            view.player = player
            grid.addView(view)
            views.add(view)
            players.add(player)

            // Stagger codec init so HW/SW decoders aren't allocated in one burst.
            val delayMs = (index * 350L)
            mainHandler.postDelayed({
                if (players.contains(player)) {
                    player.setMediaItem(MediaItem.fromUri(url))
                    player.playWhenReady = true
                    player.prepare()
                }
            }, delayMs)
        }
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
                    // Prefer software decoders for secondary multiview panes.
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

    private fun layoutDims(layout: String): Pair<Int, Int> =
        when (layout) {
            "2x1" -> 1 to 2
            "1x2" -> 2 to 1
            "2x2" -> 2 to 2
            else -> 1 to 1
        }

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
