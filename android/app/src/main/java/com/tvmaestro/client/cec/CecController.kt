package com.tvmaestro.client.cec

import android.content.Context
import android.media.AudioManager
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.KeyEvent
import java.lang.reflect.Proxy

/**
 * Best-effort CEC / TV control for HDMI playback devices (Shield, sticks, etc.).
 *
 * Volume works via AudioManager → CEC User Control when
 * `hdmi_control_volume_control_enabled=1`.
 *
 * Power: sideloaded apps are SELinux-blocked from `hdmi_control` on Shield, and
 * app-spawned `input keyevent SLEEP` is ignored by PowerManager (no CEC Standby).
 * Real power needs the TVMaestro server’s adb WAKEUP/SLEEP (or Android TV Remote).
 * We still try HDMI APIs / keys here for OEM builds that allow them.
 */
class CecController(private val context: Context) {
    private val tag = "CecController"
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    init {
        allowHiddenApis()
    }

    data class Capabilities(
        val power: Boolean,
        val volume: Boolean,
        val mute: Boolean,
        val method: String,
        val powerDetail: String = "",
    )

    private fun allowHiddenApis() {
        try {
            val vmRuntime = Class.forName("dalvik.system.VMRuntime")
            val runtime = vmRuntime.getDeclaredMethod("getRuntime").invoke(null)
            vmRuntime
                .getDeclaredMethod("setHiddenApiExemptions", Array<String>::class.java)
                .invoke(runtime, arrayOf("L"))
            Log.i(tag, "Hidden API exemptions applied")
        } catch (e: Exception) {
            Log.d(tag, "Hidden API exemption unavailable: ${e.message}")
        }
    }

    fun capabilities(): Capabilities {
        ensureOneTouchPlayEnabled()
        val mgr = hdmiManager()
        val client = mgr?.let { playbackClient(it) }
        val service = if (mgr == null) hdmiBinderService() else null
        val oneTouch = isOneTouchPlayEnabled()
        val hasHdmiApi = client != null || service != null || mgr != null
        val detail =
            buildString {
                when {
                    client != null -> append("HdmiPlaybackClient")
                    service != null -> append("IHdmiControlService binder")
                    mgr != null -> append("HdmiControlManager")
                    else ->
                        append(
                            "hdmi_control SELinux-blocked for sideloaded apps",
                        )
                }
                append("; one_touch_play=").append(if (oneTouch) "on" else "OFF")
            }
        // Only claim in-app power when we actually have the HDMI API.
        // oneTouch alone is not enough — app keyinject cannot sleep the Shield.
        return Capabilities(
            power = hasHdmiApi,
            volume = true,
            mute = true,
            method =
                when {
                    client != null -> "hdmi_playback"
                    service != null -> "hdmi_binder"
                    mgr != null -> "hdmi_api"
                    else -> "server_adb"
                },
            powerDetail = detail + "; server uses adb for power when API blocked",
        )
    }

    fun powerOn(): Boolean {
        wakeScreen()
        ensureOneTouchPlayEnabled()

        val mgr = hdmiManager()
        val client = mgr?.let { playbackClient(it) }
        if (client != null && oneTouchPlay(client)) {
            Log.i(tag, "powerOn via PlaybackClient.oneTouchPlay")
            return true
        }
        if (oneTouchPlayViaService()) {
            Log.i(tag, "powerOn via IHdmiControlService.oneTouchPlay")
            return true
        }
        if (mgr != null && invokeNoArg(mgr, "toggleAndFollowTvPower")) {
            Log.i(tag, "powerOn via toggleAndFollowTvPower")
            return true
        }
        if (mgr != null && powerRemote(mgr, on = true)) {
            Log.i(tag, "powerOn via powerOnRemoteDevice")
            return true
        }
        // App-uid keyinject does not drive Shield OTP; server adb handles power.
        Log.w(tag, "powerOn: no HDMI API (use server adb WAKEUP)")
        return false
    }

    fun powerOff(): Boolean {
        val mgr = hdmiManager()
        val client = mgr?.let { playbackClient(it) }
        if (client != null && invokeNoArg(client, "sendStandby")) {
            Log.i(tag, "powerOff via PlaybackClient.sendStandby")
            return true
        }
        if (sendStandbyViaService()) {
            Log.i(tag, "powerOff via IHdmiControlService.sendStandby")
            return true
        }
        if (mgr != null && powerRemote(mgr, on = false)) {
            Log.i(tag, "powerOff via powerOffRemoteDevice")
            return true
        }
        Log.w(tag, "powerOff: no HDMI API (use server adb SLEEP)")
        return false
    }

    fun volumeUp(): Boolean = sendVolume(AudioManager.ADJUST_RAISE)

    fun volumeDown(): Boolean = sendVolume(AudioManager.ADJUST_LOWER)

    fun mute(): Boolean {
        return try {
            audio.adjustStreamVolume(
                AudioManager.STREAM_MUSIC,
                AudioManager.ADJUST_TOGGLE_MUTE,
                AudioManager.FLAG_SHOW_UI,
            )
            dispatchMediaKey(KeyEvent.KEYCODE_VOLUME_MUTE)
            true
        } catch (e: Exception) {
            Log.w(tag, "mute failed: ${e.message}")
            false
        }
    }

    private fun ensureOneTouchPlayEnabled() {
        try {
            if (!isOneTouchPlayEnabled()) {
                Settings.Global.putInt(context.contentResolver, SETTING_ONE_TOUCH_PLAY, 1)
                Log.i(tag, "Enabled $SETTING_ONE_TOUCH_PLAY")
            }
            if (Settings.Global.getInt(context.contentResolver, SETTING_SEND_ACTIVE_SOURCE, 0) == 0) {
                Settings.Global.putInt(context.contentResolver, SETTING_SEND_ACTIVE_SOURCE, 1)
                Log.i(tag, "Enabled $SETTING_SEND_ACTIVE_SOURCE")
            }
        } catch (e: Exception) {
            Log.d(tag, "Cannot write CEC globals: ${e.message}")
        }
    }

    private fun isOneTouchPlayEnabled(): Boolean =
        try {
            Settings.Global.getInt(context.contentResolver, SETTING_ONE_TOUCH_PLAY, 0) == 1
        } catch (_: Exception) {
            false
        }

    private fun sendVolume(direction: Int): Boolean {
        return try {
            audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, AudioManager.FLAG_SHOW_UI)
            val key =
                if (direction == AudioManager.ADJUST_RAISE) {
                    KeyEvent.KEYCODE_VOLUME_UP
                } else {
                    KeyEvent.KEYCODE_VOLUME_DOWN
                }
            dispatchMediaKey(key)
            true
        } catch (e: Exception) {
            Log.w(tag, "volume failed: ${e.message}")
            false
        }
    }

    private fun dispatchMediaKey(keyCode: Int): Boolean {
        return try {
            audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
            true
        } catch (e: Exception) {
            Log.d(tag, "dispatchMediaKey($keyCode): ${e.message}")
            false
        }
    }

    private fun wakeScreen() {
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            val wl =
                pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "tvmaestro:cec",
                )
            wl.acquire(3000)
            wl.release()
        } catch (e: Exception) {
            Log.d(tag, "wakeScreen: ${e.message}")
        }
    }

    private fun hdmiManager(): Any? {
        try {
            val clazz = Class.forName("android.hardware.hdmi.HdmiControlManager")
            context.getSystemService(clazz)?.let { return it }
        } catch (_: Exception) {
        }
        try {
            context.getSystemService("hdmi_control")?.let { return it }
        } catch (_: Exception) {
        }
        return null
    }

    private fun hdmiBinderService(): Any? {
        return try {
            val sm = Class.forName("android.os.ServiceManager")
            val binder =
                sm.getMethod("getService", String::class.java).invoke(null, "hdmi_control")
            if (binder == null) {
                Log.d(tag, "ServiceManager.getService(hdmi_control)=null (often SELinux)")
                return null
            }
            val stub = Class.forName("android.hardware.hdmi.IHdmiControlService\$Stub")
            stub.getMethod("asInterface", Class.forName("android.os.IBinder")).invoke(null, binder)
        } catch (e: Exception) {
            Log.d(tag, "hdmiBinderService: ${e.message}")
            null
        }
    }

    private fun playbackClient(mgr: Any): Any? {
        for (name in listOf("getPlaybackClient", "getPlaybackClientLocked")) {
            try {
                val m =
                    mgr.javaClass.methods.firstOrNull {
                        it.name == name && it.parameterTypes.isEmpty()
                    } ?: continue
                m.invoke(mgr)?.let { return it }
            } catch (e: Exception) {
                Log.d(tag, "$name: ${e.message}")
            }
        }
        return null
    }

    private fun oneTouchPlay(client: Any): Boolean {
        for (cbName in
            listOf(
                "android.hardware.hdmi.HdmiPlaybackClient\$OneTouchPlayCallback",
                "android.hardware.hdmi.IHdmiControlCallback",
            )) {
            try {
                val callbackClass = Class.forName(cbName)
                val proxy =
                    Proxy.newProxyInstance(callbackClass.classLoader, arrayOf(callbackClass)) {
                            _,
                            method,
                            args,
                        ->
                        if (method.name == "onComplete" || method.name == "onResult") {
                            Log.i(tag, "oneTouchPlay ${method.name}=${args?.firstOrNull()}")
                        }
                        null
                    }
                val method =
                    client.javaClass.methods.firstOrNull {
                        it.name == "oneTouchPlay" && it.parameterTypes.size == 1
                    } ?: continue
                method.invoke(client, proxy)
                return true
            } catch (e: Exception) {
                Log.d(tag, "oneTouchPlay via $cbName: ${e.message}")
            }
        }
        return invokeNoArg(client, "oneTouchPlay")
    }

    private fun oneTouchPlayViaService(): Boolean {
        val service = hdmiBinderService() ?: return false
        return try {
            val callbackClass = Class.forName("android.hardware.hdmi.IHdmiControlCallback")
            val proxy =
                Proxy.newProxyInstance(callbackClass.classLoader, arrayOf(callbackClass)) {
                        _,
                        method,
                        args,
                    ->
                    if (method.name == "onComplete") {
                        Log.i(tag, "service oneTouchPlay onComplete=${args?.firstOrNull()}")
                    }
                    null
                }
            val method =
                service.javaClass.methods.firstOrNull {
                    it.name == "oneTouchPlay" && it.parameterTypes.size == 1
                } ?: return false
            method.invoke(service, proxy)
            true
        } catch (e: Exception) {
            Log.w(tag, "oneTouchPlayViaService: ${e.message}")
            false
        }
    }

    private fun sendStandbyViaService(): Boolean {
        val service = hdmiBinderService() ?: return false
        return try {
            for (m in service.javaClass.methods.filter { it.name == "sendStandby" }) {
                try {
                    when (m.parameterTypes.size) {
                        2 -> {
                            m.invoke(service, 4, 0)
                            return true
                        }
                        0 -> {
                            m.invoke(service)
                            return true
                        }
                    }
                } catch (e: Exception) {
                    Log.d(tag, "sendStandby: ${e.message}")
                }
            }
            false
        } catch (e: Exception) {
            Log.w(tag, "sendStandbyViaService: ${e.message}")
            false
        }
    }

    private fun powerRemote(mgr: Any, on: Boolean): Boolean {
        val methodName = if (on) "powerOnRemoteDevice" else "powerOffRemoteDevice"
        return try {
            for (m in mgr.javaClass.methods.filter { it.name == methodName }) {
                try {
                    when (m.parameterTypes.size) {
                        1 -> {
                            m.invoke(mgr, 0)
                            return true
                        }
                        2 -> {
                            m.invoke(mgr, 0, if (on) 0 else 1)
                            return true
                        }
                    }
                } catch (e: Exception) {
                    Log.d(tag, "$methodName: ${e.message}")
                }
            }
            false
        } catch (e: Exception) {
            Log.d(tag, "$methodName: ${e.message}")
            false
        }
    }

    private fun invokeNoArg(target: Any, name: String): Boolean {
        return try {
            val m =
                target.javaClass.methods.firstOrNull {
                    it.name == name && it.parameterTypes.isEmpty()
                } ?: return false
            m.invoke(target)
            true
        } catch (e: Exception) {
            Log.d(tag, "$name: ${e.message}")
            false
        }
    }

    companion object {
        private const val SETTING_ONE_TOUCH_PLAY = "hdmi_one_touch_play_enabled"
        private const val SETTING_SEND_ACTIVE_SOURCE = "hdmi_control_send_active_source_enabled"
    }
}
