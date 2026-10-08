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

fun layoutDims(layout: String?): Pair<Int, Int> =
    when (layout) {
        "2x1" -> 1 to 2
        "1x2" -> 2 to 1
        "2x2" -> 2 to 2
        else -> 1 to 1
    }

fun SessionSlot.isPlayable(): Boolean = !url.isNullOrBlank()
