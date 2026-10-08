package com.tvmaestro.client.web

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.tvmaestro.client.BuildConfig
import com.tvmaestro.client.DecoderCapability
import com.tvmaestro.client.GuideReach
import com.tvmaestro.client.PlaybackSession
import com.tvmaestro.client.PlayerActivity
import com.tvmaestro.client.Prefs
import com.tvmaestro.client.SessionSlot
import com.tvmaestro.client.SessionStore
import com.tvmaestro.client.isPlayable
import com.tvmaestro.client.layoutDims
import com.tvmaestro.client.cec.CecController
import fi.iki.elonen.NanoHTTPD

class ClientWebServer(
    port: Int,
    private val context: Context,
) : NanoHTTPD(port) {
    private val gson = Gson()
    private val tag = "ClientWebServer"
    private val cec = CecController(context)

    override fun serve(session: IHTTPSession): Response {
        return try {
            val uri = session.uri
            val method = session.method

            if (uri.startsWith("/api/") && uri != "/api/health" && !authorized(session)) {
                return json(mapOf("success" to false, "message" to "Unauthorized"), Response.Status.UNAUTHORIZED)
            }

            when {
                uri == "/" -> text("TVMaestro Client")
                uri == "/api/health" && method == Method.GET -> {
                    GuideReach.mark()
                    json(mapOf("success" to true, "message" to "TVMaestro Client running"))
                }
                uri == "/api/info" && method == Method.GET -> {
                    GuideReach.mark()
                    info()
                }
                uri == "/api/session" && method == Method.GET -> {
                    GuideReach.mark()
                    getSession()
                }
                uri == "/api/session" && method == Method.POST -> setSession(session)
                uri == "/api/session/stop" && method == Method.POST -> {
                    GuideReach.mark()
                    stopSession()
                }
                uri == "/api/cec" && method == Method.POST -> {
                    GuideReach.mark()
                    handleCec(session)
                }
                else -> newFixedLengthResponse(Response.Status.NOT_FOUND, MIME_PLAINTEXT, "Not Found")
            }
        } catch (e: Exception) {
            Log.e(tag, "serve error", e)
            json(mapOf("success" to false, "message" to (e.message ?: "error")))
        }
    }

    private fun authorized(session: IHTTPSession): Boolean {
        val token = Prefs.token(context)
        if (token.isEmpty()) return true
        return session.headers["x-auth-token"] == token
    }

    private fun body(session: IHTTPSession): JsonObject {
        val map = HashMap<String, String>()
        session.parseBody(map)
        val data = map["postData"] ?: "{}"
        return try {
            gson.fromJson(data, JsonObject::class.java) ?: JsonObject()
        } catch (_: Exception) {
            JsonObject()
        }
    }

    private fun info(): Response {
        val caps = cec.capabilities()
        val profile = DecoderCapability.detect()
        return json(
            mapOf(
                "model" to Build.MODEL,
                "manufacturer" to Build.MANUFACTURER,
                "androidVersion" to Build.VERSION.RELEASE,
                "sdkInt" to Build.VERSION.SDK_INT,
                "versionName" to BuildConfig.VERSION_NAME,
                "port" to Prefs.port(context),
                "hardware" to Build.HARDWARE,
                "board" to Build.BOARD,
                "device" to Build.DEVICE,
                "chip_family" to profile.chipFamily,
                "capabilities" to mapOf(
                    "multiview_max" to profile.multiviewMax,
                    "layouts" to DecoderCapability.layoutsFor(profile.multiviewMax),
                    "mpeg_ts" to true,
                    "hls" to true,
                    "weak_decoder" to profile.weakDecoder,
                    "chip_family" to profile.chipFamily,
                    "chip_note" to profile.note,
                    "cec" to mapOf(
                        "power" to caps.power,
                        "volume" to caps.volume,
                        "mute" to caps.mute,
                        "method" to caps.method,
                        "power_detail" to caps.powerDetail,
                    ),
                ),
            ),
        )
    }

    private fun getSession(): Response {
        val current = SessionStore.current
        return if (current == null) {
            json(mapOf("success" to true, "session" to null))
        } else {
            json(mapOf("success" to true, "session" to current))
        }
    }

    private fun setSession(session: IHTTPSession): Response {
        val jsonBody = body(session)
        val layout = jsonBody.get("layout")?.takeUnless { it.isJsonNull }?.asString ?: "1"
        val (rows, cols) = layoutDims(layout)
        val capacity = rows * cols
        val slotsJson = jsonBody.getAsJsonArray("slots") ?: gson.toJsonTree(emptyList<Any>()).asJsonArray
        val slots = mutableListOf<SessionSlot>()
        val limit = minOf(slotsJson.size(), capacity)
        for (i in 0 until limit) {
            val el = slotsJson[i]
            if (!el.isJsonObject) {
                slots.add(SessionSlot())
                continue
            }
            val o = el.asJsonObject
            slots.add(
                SessionSlot(
                    url = jsonString(o, "url"),
                    title = jsonString(o, "title"),
                    audio = o.get("audio")?.takeUnless { it.isJsonNull }?.asBoolean ?: false,
                    channel_id = jsonString(o, "channel_id"),
                ),
            )
        }
        while (slots.size < capacity) slots.add(SessionSlot())
        val playable = slots.count { it.isPlayable() }
        if (playable == 0) {
            return json(mapOf("success" to false, "message" to "No playable slots"), Response.Status.BAD_REQUEST)
        }
        val profile = DecoderCapability.detect()
        val max = profile.multiviewMax
        if (playable > max) {
            return json(
                mapOf(
                    "success" to false,
                    "message" to "This device supports at most $max simultaneous stream(s) (${profile.note})",
                    "multiview_max" to max,
                ),
                Response.Status.BAD_REQUEST,
            )
        }
        val playback =
            PlaybackSession(
                id = jsonString(jsonBody, "id"),
                mode = if (playable > 1) "multiview" else "single",
                layout = layout,
                slots = slots,
            )
        GuideReach.mark()
        SessionStore.set(playback)
        bringPlayerToFront()
        return json(mapOf("success" to true, "session" to playback))
    }

    private fun jsonString(obj: com.google.gson.JsonObject, key: String): String? {
        val el = obj.get(key) ?: return null
        if (el.isJsonNull) return null
        return el.asString?.takeIf { it.isNotBlank() }
    }

    private fun stopSession(): Response {
        SessionStore.set(null)
        return json(mapOf("success" to true))
    }

    private fun handleCec(session: IHTTPSession): Response {
        val action = body(session).get("action")?.asString?.lowercase()
        val ok =
            when (action) {
                "power_on" -> cec.powerOn()
                "power_off" -> cec.powerOff()
                "volume_up" -> cec.volumeUp()
                "volume_down" -> cec.volumeDown()
                "mute" -> cec.mute()
                else -> false
            }
        return json(
            mapOf(
                "success" to ok,
                "action" to action,
                "capabilities" to cec.capabilities(),
            ),
        )
    }

    private fun bringPlayerToFront() {
        val intent =
            Intent(context, PlayerActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            }
        context.startActivity(intent)
    }

    private fun json(
        data: Any,
        status: Response.Status = Response.Status.OK,
    ): Response {
        val payload = gson.toJson(data)
        return newFixedLengthResponse(status, "application/json", payload)
    }

    private fun text(msg: String): Response =
        newFixedLengthResponse(Response.Status.OK, MIME_PLAINTEXT, msg)
}
