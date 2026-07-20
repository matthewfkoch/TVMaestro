package com.tvmaestro.client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.tvmaestro.client.web.ClientWebServer

class ClientService : Service() {
    private var server: ClientWebServer? = null
    private val tag = "ClientService"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIF_ID, buildNotification())
        startServer()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (server == null) startServer()
        return START_STICKY
    }

    override fun onDestroy() {
        try {
            server?.stop()
        } catch (_: Exception) {
        }
        server = null
        super.onDestroy()
    }

    private fun startServer() {
        val port = Prefs.port(this)
        try {
            val s = ClientWebServer(port, applicationContext)
            s.start()
            server = s
            Log.i(tag, "Control API listening on $port")
        } catch (e: Exception) {
            Log.e(tag, "Failed to start server on $port", e)
        }
    }

    private fun buildNotification(): Notification {
        val channelId = "tvmaestro"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel(channelId, "TVMaestro", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val pi =
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, PlayerActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("TVMaestro")
            .setContentText("Control API on port ${Prefs.port(this)}")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pi)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val NOTIF_ID = 6790
    }
}
