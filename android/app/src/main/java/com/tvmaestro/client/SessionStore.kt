package com.tvmaestro.client

import java.util.concurrent.CopyOnWriteArrayList

object SessionStore {
    @Volatile
    var current: PlaybackSession? = null
        private set

    private val listeners = CopyOnWriteArrayList<(PlaybackSession?) -> Unit>()
    private val audioListeners = CopyOnWriteArrayList<(PlaybackSession) -> Unit>()
    private val slotListeners = CopyOnWriteArrayList<(PlaybackSession, Int) -> Unit>()

    fun set(session: PlaybackSession?) {
        current = session
        listeners.forEach { it(session) }
    }

    /** Swap which pane is audible without notifying a full session rebuild. */
    fun updateAudio(session: PlaybackSession) {
        current = session
        audioListeners.forEach { it(session) }
    }

    /** Replace one pane without notifying a full session rebuild. */
    fun updateSlot(session: PlaybackSession, index: Int) {
        current = session
        slotListeners.forEach { it(session, index) }
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

    fun addSlotListener(listener: (PlaybackSession, Int) -> Unit) {
        slotListeners.add(listener)
    }

    fun removeSlotListener(listener: (PlaybackSession, Int) -> Unit) {
        slotListeners.remove(listener)
    }
}
