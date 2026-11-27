package com.tvmaestro.client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DecoderAndLayoutTest {
    @Test
    fun detectsNvidiaShieldAsFourStreamCapable() {
        val profile = DecoderCapability.detectFrom(
            manufacturer = "NVIDIA",
            fields = listOf("NVIDIA", "SHIELD Android TV", "mdarcy", "tegra"),
        )
        assertEquals(4, profile.multiviewMax)
        assertEquals("nvidia_tegra", profile.chipFamily)
        assertFalse(profile.weakDecoder)
    }

    @Test
    fun detectsAmlogicAndMediatekAsSingleStream() {
        val amlogic = DecoderCapability.detectFrom(
            manufacturer = "onn",
            fields = listOf("onn", "4K Streaming Box", "meson"),
        )
        assertEquals(1, amlogic.multiviewMax)
        assertEquals("amlogic", amlogic.chipFamily)
        assertTrue(amlogic.weakDecoder)

        val mtk = DecoderCapability.detectFrom(
            manufacturer = "Amazon",
            fields = listOf("Amazon", "mt8696"),
        )
        assertEquals(1, mtk.multiviewMax)
        assertEquals("mediatek", mtk.chipFamily)
        assertTrue(mtk.weakDecoder)
    }

    @Test
    fun detectsRockchipAsTwoStreamAndUnknownAsConservativeSingle() {
        val rk = DecoderCapability.detectFrom(
            manufacturer = "Generic",
            fields = listOf("rk3588"),
        )
        assertEquals(2, rk.multiviewMax)
        assertEquals("rockchip", rk.chipFamily)

        val unknown = DecoderCapability.detectFrom(
            manufacturer = "Acme",
            fields = listOf("MysteryBox"),
        )
        assertEquals(1, unknown.multiviewMax)
        assertEquals("unknown", unknown.chipFamily)
        assertTrue(unknown.weakDecoder)
    }

    @Test
    fun layoutsAndSlotPlayabilityMatchContract() {
        assertEquals(listOf("1"), DecoderCapability.layoutsFor(1))
        assertEquals(listOf("1", "2x1", "1x2"), DecoderCapability.layoutsFor(2))
        assertEquals(listOf("1", "2x1", "1x2", "2x2"), DecoderCapability.layoutsFor(4))

        assertEquals(1 to 1, layoutDims("1"))
        assertEquals(1 to 2, layoutDims("2x1"))
        assertEquals(2 to 1, layoutDims("1x2"))
        assertEquals(2 to 2, layoutDims("2x2"))
        assertEquals(1 to 1, layoutDims("unknown"))

        assertFalse(SessionSlot(url = null).isPlayable())
        assertFalse(SessionSlot(url = "   ").isPlayable())
        assertTrue(SessionSlot(url = "http://dvr.local/stream.ts").isPlayable())
    }
}
