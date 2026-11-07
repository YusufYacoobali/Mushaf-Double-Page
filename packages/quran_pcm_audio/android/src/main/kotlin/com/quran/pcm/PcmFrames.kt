package com.quran.pcm

/** Streaming rational resampler. Chunk boundaries do not reset interpolation
 * phase. Equal-rate recordings retain every sample exactly; mono duplicates
 * into stereo. No amplitude-based trimming, fades, overlap, or silence. */
internal class PcmFrames(private val inputRate: Int, private val channels: Int) {
    init { require(inputRate in 8000..192000 && channels in 1..2) }
    private var pending = ShortArray(0)
    private var base = 0L
    private var total = 0L
    private var output = 0L

    fun convert(samples: ShortArray, end: Boolean = false): ShortArray {
        require(samples.size % channels == 0)
        val data = pending + samples
        total += samples.size / channels
        val result = ShortArray(((data.size / channels + 2L) * 44100 / inputRate + 2).toInt() * 2)
        var size = 0
        val limit = total * 44100 / inputRate
        while (output < limit) {
            val numerator = output * inputRate
            val frame = numerator / 44100
            if (!end && frame + 1 >= total) break
            val next = minOf(frame + 1, total - 1)
            val fraction = (numerator % 44100).toDouble() / 44100
            for (channel in 0..1) {
                val c = minOf(channel, channels - 1)
                val a = data[((frame - base) * channels).toInt() + c].toInt()
                val b = data[((next - base) * channels).toInt() + c].toInt()
                result[size++] = (a + (b - a) * fraction).toInt().coerceIn(-32768, 32767).toShort()
            }
            output++
        }
        val retain = minOf(total, output * inputRate / 44100)
        pending = data.copyOfRange(((retain - base) * channels).toInt(), data.size)
        base = retain
        return result.copyOf(size)
    }
}

/** Apply only extractor-declared encoder delay/padding, before resampling.
 * Configure MediaCodec with delay/padding zero so there is one trim owner. */
internal class GaplessFrames(delay: Int, private val padding: Int, private val channels: Int) {
    private var skip = delay
    private var tail = ShortArray(0)
    init { require(delay in 0..16384 && padding in 0..16384 && channels in 1..2) }
    fun append(samples: ShortArray, end: Boolean = false): ShortArray {
        val remove = minOf(skip, samples.size / channels)
        skip -= remove
        val data = tail + samples.copyOfRange(remove * channels, samples.size)
        val keep = minOf(data.size, padding * channels)
        val result = data.copyOfRange(0, data.size - keep)
        tail = if (end) ShortArray(0) else data.copyOfRange(data.size - keep, data.size)
        return result
    }
}
