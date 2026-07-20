package com.tvmaestro.client

import java.util.concurrent.CopyOnWriteArrayList

object SessionStore {
    @Volatile
    var current: PlaybackSession? = null
        private set

    private val listeners = CopyOnWriteArrayList<(PlaybackSession?) -> Unit>()

    fun set(session: PlaybackSession?) {
        current = session
        listeners.forEach { it(session) }
    }

    fun addListener(listener: (PlaybackSession?) -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: (PlaybackSession?) -> Unit) {
        listeners.remove(listener)
    }
}
