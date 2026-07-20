package com.tvmaestro.client

import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
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
        val cecReport = findViewById<TextView>(R.id.cecReport)
        val saveButton = findViewById<Button>(R.id.saveButton)
        val testWake = findViewById<Button>(R.id.testWakeButton)
        val testSleep = findViewById<Button>(R.id.testSleepButton)
        val testVolume = findViewById<Button>(R.id.testCecButton)

        portInput.setText(Prefs.port(this).toString())
        tokenInput.setText(Prefs.token(this))
        serverInput.setText(Prefs.serverUrl(this))

        val cec = CecController(this)
        val caps = cec.capabilities()
        val selfIp = ServerCec.localIpv4() ?: "?"
        cecReport.text =
            buildString {
                append("This device LAN IP: $selfIp\n")
                append("Volume/mute: local CEC via AudioManager\n")
                append("Wake/Sleep: TVMaestro server → Android TV Remote (or adb fallback)\n")
                append("Local HDMI power API: ${if (caps.power) "available" else "blocked (normal on Shield)"}\n")
                append(caps.powerDetail)
            }

        testVolume.setOnClickListener {
            val ok = cec.volumeUp()
            Toast.makeText(
                this,
                if (ok) "Volume up sent (CEC)" else "Volume failed — check HDMI-CEC volume settings",
                Toast.LENGTH_LONG,
            ).show()
        }

        testWake.setOnClickListener { runServerAction("power_on") }
        testSleep.setOnClickListener { runServerAction("power_off") }

        saveButton.setOnClickListener {
            val port = portInput.text.toString().toIntOrNull() ?: 9093
            Prefs.setPort(this, port)
            Prefs.setToken(this, tokenInput.text.toString())
            Prefs.setServerUrl(this, serverInput.text.toString())
            stopService(Intent(this, ClientService::class.java))
            startForegroundServiceCompat(Intent(this, ClientService::class.java))
            Toast.makeText(this, "Saved", Toast.LENGTH_SHORT).show()
            finish()
        }
    }

    private fun runServerAction(action: String) {
        // Persist URL from the field so Save isn't required first.
        val serverInput = findViewById<EditText>(R.id.serverUrlInput)
        Prefs.setServerUrl(this, serverInput.text.toString())
        Toast.makeText(this, "Requesting…", Toast.LENGTH_SHORT).show()
        thread {
            val msg = ServerCec.request(this, action)
            runOnUiThread {
                Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun startForegroundServiceCompat(intent: Intent) {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
