package com.tvmaestro.client

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.tvmaestro.client.cec.CecController
import kotlin.concurrent.thread

class SettingsActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)

        val portInput = findViewById<EditText>(R.id.portInput)
        val tokenInput = findViewById<EditText>(R.id.tokenInput)
        val serverInput = findViewById<EditText>(R.id.serverUrlInput)
        val deviceSummary = findViewById<TextView>(R.id.deviceSummary)
        val powerDetail = findViewById<TextView>(R.id.powerDetail)
        val actionStatus = findViewById<TextView>(R.id.actionStatus)
        val saveButton = findViewById<Button>(R.id.saveButton)
        val testWake = findViewById<Button>(R.id.testWakeButton)
        val testSleep = findViewById<Button>(R.id.testSleepButton)
        val testVolume = findViewById<Button>(R.id.testCecButton)

        portInput.setText(Prefs.port(this).toString())
        tokenInput.setText(Prefs.token(this))
        serverInput.setText(Prefs.serverUrl(this))

        val cec = CecController(this)
        val caps = cec.capabilities()
        val profile = DecoderCapability.detect()
        val selfIp = ServerCec.localIpv4() ?: getString(R.string.no_lan)
        val address = if (selfIp.contains(" ")) selfIp else "$selfIp:${Prefs.port(this)}"
        val streams =
            if (profile.multiviewMax <= 1) {
                getString(R.string.streams_one)
            } else {
                getString(R.string.streams_many, profile.multiviewMax)
            }
        deviceSummary.text = "$address\n$streams"
        powerDetail.text =
            buildString {
                append("Local HDMI power API: ")
                append(if (caps.power) "available" else "blocked (normal on Shield)")
                if (caps.powerDetail.isNotBlank()) {
                    append("\n")
                    append(caps.powerDetail)
                }
            }

        testVolume.setOnClickListener {
            val ok = cec.volumeUp()
            showStatus(
                actionStatus,
                if (ok) "Volume up sent (CEC)" else "Volume failed — check HDMI-CEC volume settings",
                ok,
            )
        }

        testWake.setOnClickListener { runServerAction(actionStatus, "power_on") }
        testSleep.setOnClickListener { runServerAction(actionStatus, "power_off") }

        saveButton.setOnClickListener {
            val port = (portInput.text.toString().toIntOrNull() ?: 9093).coerceIn(1024, 65535)
            Prefs.setPort(this, port)
            Prefs.setToken(this, tokenInput.text.toString())
            Prefs.setServerUrl(this, serverInput.text.toString())
            stopService(Intent(this, ClientService::class.java))
            startForegroundServiceCompat(Intent(this, ClientService::class.java))
            showStatus(actionStatus, getString(R.string.saved), true)
            finish()
        }
    }

    private fun showStatus(view: TextView, message: String, ok: Boolean) {
        view.visibility = android.view.View.VISIBLE
        view.text = message
        view.setTextColor(getColor(if (ok) R.color.accent else R.color.warn))
    }

    private fun runServerAction(status: TextView, action: String) {
        val serverInput = findViewById<EditText>(R.id.serverUrlInput)
        Prefs.setServerUrl(this, serverInput.text.toString())
        showStatus(status, "Requesting…", true)
        thread {
            val msg = ServerCec.request(this, action)
            val ok = msg.contains(" ok via")
            runOnUiThread { showStatus(status, msg, ok) }
        }
    }

    private fun startForegroundServiceCompat(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
