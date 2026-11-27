package com.quran.pcm

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject
import java.io.File

/** Requires an Android runtime, and then physical output capture for gap claims.
 * The reference counts come from independently decoded, unmodified EveryAyah MP3s. */
@RunWith(AndroidJUnit4::class)
class PcmOutputDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().context
    private fun fixture(name: String): File {
        val file = File(context.cacheDir, name.substringAfterLast('/'))
        context.assets.open(name).use { input -> file.outputStream().use { input.copyTo(it) } }
        return file
    }
    @Test fun decoderMatchesIndependentReferenceFrameCounts() {
        val references = JSONObject(context.assets.open("pcm-reference.json").bufferedReader().use { it.readText() })
        for (name in references.keys()) {
            val file = fixture(name)
            var frames = 0L
            var peak = 0
            Mp3Decoder.decode(file.path, { false }) {
                frames += it.size / 2
                peak = maxOf(peak, it.size)
            }
            assertEquals(name, references.getLong(name), frames)
            assertTrue("Decoder chunks must remain bounded", peak < 65536)
        }
    }
    @Test fun stereoCorrectionPreservesEveryFrameOfTheOriginalRecordings() {
        for ((name, affected) in listOf("gapless/abdullah_juhany-112002.mp3" to true,
                "bismillah/abdullah_juhany.mp3" to false, "gapless/alafasy-112002.mp3" to false)) {
            val path = fixture(name).path
            assertEquals(name, affected, Mp3Decoder.needsCorrection(path) { false })
            val original = ArrayDeque<ShortArray>()
            Mp3Decoder.decode(path, { false }, false) { original.addLast(it) }
            var offset = 0
            var frames = 0
            Mp3Decoder.decode(path, { false }) { output ->
                for (sample in output) {
                    val first = original.first()
                    val raw = first[offset]
                    val right = offset % 2 != 0
                    val expected = if (affected && right) (-raw.toInt()).coerceAtMost(32767).toShort() else raw
                    if (sample != expected) fail("$name: wrong sample at frame $frames (right=$right)")
                    if (right) frames++
                    if (++offset == first.size) { original.removeFirst(); offset = 0 }
                }
            }
            assertTrue(name, frames > 0 && original.isEmpty())
        }
    }

    @Test fun oneOutputRetainsExactOccurrenceBoundsAndPauseIntent() {
        val file = fixture("gapless/alafasy-112001.mp3")
        var frames = 0L
        Mp3Decoder.decode(file.path, { false }) { frames += it.size / 2 }
        val output = PcmOutput(1, 1, 0)
        try {
            for (i in 0..2) output.enqueue("occurrence-$i", file.path)
            output.start()
            output.finish()
            output.setPlaying(true)
            val deadline = System.nanoTime() + 90_000_000_000L
            var last = 0L
            var testedPause = false
            while (System.nanoTime() < deadline) {
                val snapshot = output.snapshot()
                assertNull(snapshot["error"])
                val played = snapshot["frames"] as Long
                assertTrue(played >= last)
                assertTrue((snapshot["pcmBufferedFrames"] as Long) < 44100 + 44100 / 2)
                @Suppress("UNCHECKED_CAST")
                val rows = snapshot["rows"] as List<Map<String, Any?>>
                rows.forEachIndexed { index, row ->
                    assertEquals(index * frames, row["start"])
                    if (row["end"] != null) assertEquals((index + 1) * frames, row["end"])
                }
                if (!testedPause && played > 4410) {
                    output.setPlaying(false)
                    val paused = output.snapshot()["frames"]
                    Thread.sleep(250)
                    assertEquals(paused, output.snapshot()["frames"])
                    output.setPlaying(true)
                    testedPause = true
                }
                if (snapshot["state"] == "completed") {
                    assertEquals(frames * 3, played)
                    assertTrue(testedPause)
                    return
                }
                last = played
                Thread.sleep(50)
            }
            fail("Continuous native output did not finish")
        } finally { output.cancel() }
    }
}
