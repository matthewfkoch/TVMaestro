package com.tvmaestro.client

import java.util.concurrent.CopyOnWriteArrayList

object SessionStore {
    @Volatile
    var current: PlaybackSession? = null
        private set

    private val listeners = CopyOnWriteArrayList<(PlaybackSession?) -> Unit>()
    private val audioListeners = CopyOnWriteArrayList<(PlaybackSession) -> Unit>()

    fun set(session: PlaybackSession?) {
        current = session
        listeners.forEach { it(session) }
    }

    /** Swap which pane is audible without notifying a full session rebuild. */
    fun updateAudio(session: PlaybackSession) {
        current = session
        audioListeners.forEach { it(session) }
    }

    fun addListener(listener: (PlaybackSession?) -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: (PlaybackSession?) -> Unit) {
        listeners.remove(listener)
    }

    fun addAudioListener(listener: (PlaybackSession) -> Unit) {
        audioListeners.add(listener)
    }

    fun removeAudioListener(listener: (PlaybackSession) -> Unit) {
        audioListeners.remove(listener)
    }
}
