package com.tvmaestro.client

import android.content.Context
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.URL
import org.json.JSONObject

object ServerCec {
    fun localIpv4(): String? {
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return null
            for (iface in interfaces) {
                if (!iface.isUp || iface.isLoopback) continue
                for (addr in iface.inetAddresses) {
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        return addr.hostAddress
                    }
                }
            }
        } catch (_: Exception) {
        }
        return null
    }

    /**
     * Ask the TVMaestro server to wake/sleep this device via adb.
     * Returns a short status message for the UI.
     */
    fun request(
        context: Context,
        action: String,
    ): String {
        val base = Prefs.serverUrl(context)
        if (base.isBlank()) {
            return "Set TVMaestro server URL first (e.g. http://tvmaestro.local:6790)"
        }
        val host = localIpv4()
            ?: return "Could not determine this device's LAN IP"
        return try {
            val url = URL("$base/api/cec/by-host")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 8000
                readTimeout = 12000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
            conn.outputStream.use { os ->
                os.write(JSONObject().put("host", host).put("action", action).toString().toByteArray())
            }
            val code = conn.responseCode
            val body =
                (if (code in 200..299) conn.inputStream else conn.errorStream)
                    ?.bufferedReader()
                    ?.readText()
                    .orEmpty()
            if (code !in 200..299) {
                return "Server HTTP $code: ${body.take(160)}"
            }
            val json = runCatching { JSONObject(body) }.getOrNull()
            val ok = json?.optBoolean("success", false) == true
            val method = json?.optString("method").orEmpty()
            val msg = json?.optString("message").orEmpty()
            if (ok) {
                val label = if (action == "power_on") "Wake" else "Sleep"
                "$label ok via ${method.ifBlank { "server" }}"
            } else {
                msg.ifBlank { "Request failed" }
            }
        } catch (e: Exception) {
            "Could not reach server: ${e.message}"
        }
    }
}
