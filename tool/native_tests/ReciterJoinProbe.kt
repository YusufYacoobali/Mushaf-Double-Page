package com.quran.pcm

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.json.JSONObject

/** Run in Android's app_process against the production decoder and AudioTrack.
 * Each nonempty input line is one cached selection of up to six local paths.
 * Raw decode output is optional and is never written to the app's cache. */
fun main(args: Array<String>) {
    val selections = File(args[0]).readLines().filter { it.isNotBlank() }
    val outputDir = File(args[1]).also { it.mkdirs() }
    for ((index, line) in selections.withIndex()) {
        val paths = line.split(" ")
        if (args.getOrNull(2) == "decode") {
            for (path in paths.distinct()) {
                val file = File(path)
                val pcm = File(outputDir, file.parentFile!!.name + "-" + file.nameWithoutExtension + ".s16")
                pcm.outputStream().buffered().use { output ->
                    Mp3Decoder.decode(path, { false }) { samples ->
                        val buffer = ByteBuffer.allocate(samples.size * 2).order(ByteOrder.LITTLE_ENDIAN)
                        buffer.asShortBuffer().put(samples)
                        output.write(buffer.array())
                    }
                }
                println(JSONObject(mapOf("path" to path, "decodedFrames" to pcm.length() / 4)))
            }
            continue
        }
        require(paths.size <= 6)
        val output = PcmOutput(index.toLong(), 8, 0)
        try {
            for ((i, path) in paths.withIndex()) output.enqueue("verse-$i", path)
            output.start()
            output.finish()
            val began = System.nanoTime()
            output.setPlaying(true)
            var lastRows = ""
            var lastSecond = -1L
            while (true) {
                val snapshot = output.snapshot()
                val second = (System.nanoTime() - began) / 1_000_000_000L
                val rows = (snapshot["rows"] as List<*>).size.toString()
                if (rows != lastRows || second != lastSecond || snapshot["state"] == "completed" || snapshot["error"] != null) {
                    println(JSONObject(snapshot + mapOf("paths" to paths, "elapsedMs" to (System.nanoTime()-began)/1_000_000)))
                    lastRows = rows
                    lastSecond = second
                }
                check(snapshot["error"] == null) { snapshot["error"].toString() }
                if (snapshot["state"] == "completed") break
                check(second < 1200) { "Playback timed out" }
                Thread.sleep(100)
            }
        } finally { output.cancel() }
    }
}
