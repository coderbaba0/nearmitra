package com.farmitra.nearby

import org.junit.Assert.*
import org.junit.Test

class PhoneAudioPcmTest {
    @Test fun tcpSplitsNeverDropOrMisalignStereoSamples() {
        val frames = PhoneAudioFrames()
        val source = ByteArray(400) { it.toByte() }
        val received = mutableListOf<Byte>()
        var offset = 0
        for (count in listOf(1, 3, 7, 2, 23, 101, 263)) {
            val out = frames.consume(source.copyOfRange(offset, offset + count), count)
            assertEquals(0, out.size % PhoneAudioPcm.FRAME_BYTES)
            received.addAll(out.toList())
            offset += count
        }
        assertArrayEquals(source, received.toByteArray())
    }
    @Test fun playbackFormatHasExactlyTwentyMillisecondBlocks() {
        assertEquals(3840, PhoneAudioPcm.BLOCK_BYTES)
        assertEquals(PhoneAudioPcm.RATE * 2 * 2 / 50, PhoneAudioPcm.BLOCK_BYTES)
    }
    @Test fun meterReadsLittleEndianPcmAndDoesNotInventEnergy() {
        assertEquals(0.0, PhoneAudioPcm.level(ByteArray(100), 100), 0.0)
        // Positive and negative half-scale samples.
        assertEquals(0.5, PhoneAudioPcm.level(byteArrayOf(0, 64, 0, -64), 4), 0.00001)
    }
}
