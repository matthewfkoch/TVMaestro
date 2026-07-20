package com.tvmaestro.client

import android.os.Build

/**
 * Classify SoC / device class for concurrent HD decode capacity.
 * Low-end Amlogic / MediaTek sticks typically only sustain one 1080p HW decoder.
 */
object DecoderCapability {
    data class Profile(
        val multiviewMax: Int,
        val chipFamily: String,
        val weakDecoder: Boolean,
        val note: String,
    )

    fun detect(): Profile {
        val socManufacturer =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MANUFACTURER else ""
        val socModel =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MODEL else ""
        val hay =
            listOf(
                Build.MANUFACTURER,
                Build.BRAND,
                Build.MODEL,
                Build.DEVICE,
                Build.PRODUCT,
                Build.BOARD,
                Build.HARDWARE,
                socManufacturer,
                socModel,
            ).joinToString(" ").lowercase()

        // Known capable: NVIDIA Shield / Tegra
        if (
            hay.contains("tegra") ||
            hay.contains("nvidia") ||
            hay.contains("shield") ||
            hay.contains("darcy") ||
            hay.contains("foster") ||
            hay.contains("mdarcy")
        ) {
            return Profile(
                multiviewMax = 4,
                chipFamily = "nvidia_tegra",
                weakDecoder = false,
                note = "NVIDIA Tegra — multi HW decode OK",
            )
        }

        // Weak: Amlogic (onn, many Fire TV sticks)
        if (
            hay.contains("amlogic") ||
            hay.contains("meson") ||
            Build.MANUFACTURER.equals("onn", ignoreCase = true) ||
            hay.contains("sheldon") ||
            hay.contains("aftss") ||
            hay.contains("aftmm") ||
            hay.contains("aftka") ||
            hay.contains("aftnms")
        ) {
            return Profile(
                multiviewMax = 1,
                chipFamily = "amlogic",
                weakDecoder = true,
                note = "Amlogic — single HD decoder; multiview disabled",
            )
        }

        // Weak: MediaTek sticks
        if (
            hay.contains("mediatek") ||
            hay.contains("mt58") ||
            hay.contains("mt87") ||
            hay.contains("mt96") ||
            Regex("""\bmt\d{2,4}\b""").containsMatchIn(hay)
        ) {
            return Profile(
                multiviewMax = 1,
                chipFamily = "mediatek",
                weakDecoder = true,
                note = "MediaTek stick — multiview disabled",
            )
        }

        // Mid: Rockchip can sometimes do 2
        if (hay.contains("rockchip") || hay.contains("rk33") || hay.contains("rk35")) {
            return Profile(
                multiviewMax = 2,
                chipFamily = "rockchip",
                weakDecoder = false,
                note = "Rockchip — up to 2 panes",
            )
        }

        // Conservative default: unknown SoCs get single-view only
        return Profile(
            multiviewMax = 1,
            chipFamily = "unknown",
            weakDecoder = true,
            note = "Unknown SoC — multiview disabled",
        )
    }

    fun layoutsFor(max: Int): List<String> =
        when {
            max >= 4 -> listOf("1", "2x1", "1x2", "2x2")
            max >= 2 -> listOf("1", "2x1", "1x2")
            else -> listOf("1")
        }
}
