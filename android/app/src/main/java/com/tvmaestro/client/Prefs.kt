package com.tvmaestro.client

import android.content.Context

object Prefs {
    private const val NAME = "tvmaestro"
    private const val KEY_PORT = "port"
    private const val KEY_TOKEN = "token"
    private const val KEY_SERVER_URL = "server_url"

    fun port(context: Context): Int =
        context.getSharedPreferences(NAME, Context.MODE_PRIVATE).getInt(KEY_PORT, 9093)

    fun setPort(context: Context, port: Int) {
        context.getSharedPreferences(NAME, Context.MODE_PRIVATE).edit().putInt(KEY_PORT, port).apply()
    }

    fun token(context: Context): String =
        context.getSharedPreferences(NAME, Context.MODE_PRIVATE).getString(KEY_TOKEN, "") ?: ""

    fun setToken(context: Context, token: String) {
        context.getSharedPreferences(NAME, Context.MODE_PRIVATE).edit().putString(KEY_TOKEN, token).apply()
    }

    /** Base URL of the TVMaestro server, e.g. http://tvmaestro.local:6790 */
    fun serverUrl(context: Context): String =
        context.getSharedPreferences(NAME, Context.MODE_PRIVATE).getString(KEY_SERVER_URL, "") ?: ""

    fun setServerUrl(context: Context, url: String) {
        context
            .getSharedPreferences(NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_SERVER_URL, url.trim().trimEnd('/'))
            .apply()
    }
}
