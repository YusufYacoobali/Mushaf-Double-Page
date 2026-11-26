package com.quran.pcm

import org.junit.Assert.*
import org.junit.Test

class PcmFramesTest {
    @Test fun sameRatePreservesEverySampleAcrossArbitraryChunks() {
        val input = ShortArray(44100 * 2) { ((it * 73) % 65536 - 32768).toShort() }
        val converter = PcmFrames(44100, 2)
        val result = ArrayList<Short>()
        input.asList().chunked(158).forEach { result.addAll(converter.convert(it.toShortArray()).asList()) }
        result.addAll(converter.convert(ShortArray(0), true).asList())
        assertArrayEquals(input, result.toShortArray())
    }
    @Test fun resamplingIsIndependentOfChunkSizeAndHasExactRationalCount() {
        for (rate in listOf(16000, 22050, 24000, 32000, 44100, 48000)) {
            for (channels in 1..2) {
                val input = ShortArray(rate * channels + 123 * channels) { (it % 1024).toShort() }
                val once = PcmFrames(rate, channels).convert(input, true)
                val converter = PcmFrames(rate, channels)
                val chunks = ArrayList<Short>()
                input.asList().chunked(73 * channels).forEach { chunks.addAll(converter.convert(it.toShortArray()).asList()) }
                chunks.addAll(converter.convert(ShortArray(0), true).asList())
                assertArrayEquals("$rate/$channels", once, chunks.toShortArray())
                assertEquals((input.size.toLong() / channels * 44100 / rate * 2).toInt(), once.size)
            }
        }
    }
    @Test fun monoDuplicatesChannelsAndKeepsQuietSamples() {
        val input = shortArrayOf(0, 0, 19, -19, 0, 0)
        val output = PcmFrames(44100, 1).convert(input, true)
        assertArrayEquals(input.flatMap { listOf(it, it) }.toShortArray(), output)
    }
    @Test fun metadataTrimHasOneOwnerAndKeepsNaturalSilence() {
        val input = shortArrayOf(9, 9, 0, 0, 31, 31, 0, 0, 8, 8)
        val trimmer = GaplessFrames(1, 1, 2)
        val result = ArrayList<Short>()
        input.asList().chunked(2).forEach { result.addAll(trimmer.append(it.toShortArray()).asList()) }
        result.addAll(trimmer.append(ShortArray(0), true).asList())
        assertArrayEquals(shortArrayOf(0, 0, 31, 31, 0, 0), result.toShortArray())
        assertArrayEquals(input, GaplessFrames(0, 0, 2).append(input, true))
    }
    @Test(expected = IllegalArgumentException::class)
    fun invalidMetadataCannotAllocateAnUnboundedTail() { GaplessFrames(0, Int.MAX_VALUE, 2) }

    @Test fun tinyRecordingCacheReusesArraysAndEvictsWithinItsBudget() {
        val cache = PcmCache(20)
        val samples = ShortArray(24)
        cache.put("a", listOf(samples))
        assertSame(samples, cache["a"]!![0])
        for (i in 0..1000) {
            cache.put("$i", listOf(ShortArray(18)))
            assertTrue(cache.frames <= 20)
        }
        assertNull(cache["a"])
        cache.put("long", listOf(ShortArray(1000)))
        assertNull(cache["long"])
    }
}
