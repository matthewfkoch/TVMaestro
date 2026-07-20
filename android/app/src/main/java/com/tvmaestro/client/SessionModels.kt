package com.tvmaestro.client

data class SessionSlot(
    val url: String? = null,
    val title: String? = null,
    val audio: Boolean = false,
    val channel_id: String? = null,
)

data class PlaybackSession(
    val id: String? = null,
    val mode: String? = "single",
    val layout: String? = "1",
    val slots: List<SessionSlot> = emptyList(),
)
