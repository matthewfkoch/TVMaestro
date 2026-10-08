package com.tvmaestro.client

import java.util.concurrent.CopyOnWriteArrayList

/** Set when the guide reaches the control API during this process. */
object GuideReach {
    @Volatile
    var connected: Boolean = false
        private set

    private val listeners = CopyOnWriteArrayList<(Boolean) -> Unit>()

    fun mark() {
        if (connected) return
        connected = true
        listeners.forEach { it(true) }
    }

    fun addListener(listener: (Boolean) -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: (Boolean) -> Unit) {
        listeners.remove(listener)
    }
}
