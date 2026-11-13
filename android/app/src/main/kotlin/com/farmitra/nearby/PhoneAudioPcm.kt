package com.farmitra.nearby

import kotlin.math.sqrt

/** Wire format is fixed: 48 kHz, stereo, signed PCM16 little endian. */
internal object PhoneAudioPcm {
    const val RATE = 48000
    const val CHANNELS = 2
    const val FRAME_BYTES = CHANNELS * 2
    const val BLOCK_BYTES = RATE / 50 * FRAME_BYTES // 20 ms, no resampling.

    fun level(bytes: ByteArray, count: Int): Double {
        if (count < 2) return 0.0
        var energy = 0.0
        for (i in 0 until count - 1 step 2) {
            val sample = ((bytes[i].toInt() and 255) or (bytes[i + 1].toInt() shl 8)).toShort().toDouble() / 32768.0
            energy += sample * sample
        }
        return sqrt(energy / (count / 2)).coerceIn(0.0, 1.0)
    }
}

/** TCP may split a sample/frame anywhere. Keep at most one partial frame. */
internal class PhoneAudioFrames {
    private var tail = ByteArray(0)
    fun consume(bytes: ByteArray, count: Int): ByteArray {
        val combined = tail + bytes.copyOf(count)
        val size = combined.size / PhoneAudioPcm.FRAME_BYTES * PhoneAudioPcm.FRAME_BYTES
        tail = combined.copyOfRange(size, combined.size)
        return combined.copyOf(size)
    }
}
