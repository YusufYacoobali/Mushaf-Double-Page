package com.quran.pcm

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.nio.ByteOrder
import java.util.concurrent.CancellationException

internal object Mp3Decoder {
    /** One codec output chunk at a time, with backpressure supplied by emit. */
    fun decode(path: String, cancelled: () -> Boolean, invert: Boolean = false, emit: (ShortArray) -> Unit) {
        read(path, cancelled, null, invert, emit)
    }

    fun needsCorrection(path: String, cancelled: () -> Boolean): Boolean = try {
        StereoPolarity.needsCorrection { position ->
            val window = StereoWindow()
            read(path, cancelled, position, emit = window::add)
            window.energies()
        }
    } catch (error: CancellationException) {
        throw error
    } catch (_: Exception) {
        false // An unavailable probe must never prevent original playback.
    }

    // Probe short, separated excerpts through a separate extractor. Seeking the
    // probe must never disturb the primary decoder's bit reservoir or trim.
    private fun read(path: String, cancelled: () -> Boolean, probe: Double?, invert: Boolean = false, emit: (ShortArray) -> Unit) {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(path)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: error("Recording has no audio track")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            require(format.getString(MediaFormat.KEY_MIME) == "audio/mpeg") { "Expected original MP3 recording" }
            val rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            fun integer(key: String) = if (format.containsKey(key)) format.getInteger(key) else 0
            var warmup = rate * 80 / 1000
            var remaining = rate * 400 / 1000
            if (probe != null) {
                val durationUs = if (format.containsKey(MediaFormat.KEY_DURATION)) format.getLong(MediaFormat.KEY_DURATION) else 0L
                require(channels == 2 && durationUs >= 900_000)
                extractor.seekTo(((durationUs - 480_000) * probe).toLong(), MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            }
            val trim = GaplessFrames(integer(MediaFormat.KEY_ENCODER_DELAY), integer(MediaFormat.KEY_ENCODER_PADDING), channels)
            val resample = PcmFrames(rate, channels)
            format.setInteger(MediaFormat.KEY_ENCODER_DELAY, 0)
            format.setInteger(MediaFormat.KEY_ENCODER_PADDING, 0)
            format.setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            val decoder = MediaCodec.createDecoderByType("audio/mpeg")
            codec = decoder
            decoder.configure(format, null, null, 0)
            decoder.start()
            val info = MediaCodec.BufferInfo()
            var inputEnded = false
            var lastProgress = System.nanoTime()
            var frames = 0L
            while (!cancelled()) {
                if (!inputEnded) {
                    val index = decoder.dequeueInputBuffer(10000)
                    if (index >= 0) {
                        val input = decoder.getInputBuffer(index)!!
                        val size = extractor.readSampleData(input, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputEnded = true
                        } else {
                            decoder.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                when (val index = decoder.dequeueOutputBuffer(info, 10000)) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val actual = decoder.outputFormat
                        require(actual.getInteger(MediaFormat.KEY_SAMPLE_RATE) == rate &&
                            actual.getInteger(MediaFormat.KEY_CHANNEL_COUNT) == channels) { "Decoder changed source format" }
                        require(!actual.containsKey(MediaFormat.KEY_PCM_ENCODING) ||
                            actual.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_16BIT) { "Unsupported PCM encoding" }
                    }
                    else -> if (index >= 0) {
                        val ended = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        val buffer = decoder.getOutputBuffer(index)!!
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        val samples = ShortArray(info.size / 2)
                        buffer.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(samples)
                        decoder.releaseOutputBuffer(index, false)
                        if (probe != null) {
                            val available = samples.size / 2
                            val skip = minOf(warmup, available)
                            warmup -= skip
                            val take = minOf(remaining, available - skip)
                            if (take > 0) emit(samples.copyOfRange(skip * 2, (skip + take) * 2))
                            remaining -= take
                            if (remaining == 0 || ended) return
                            lastProgress = System.nanoTime()
                            continue
                        }
                        val converted = resample.convert(trim.append(samples, end = ended), end = ended)
                        if (converted.isNotEmpty()) {
                            if (invert && channels == 2) StereoPolarity.restore(converted)
                            if (converted.size <= 8192) emit(converted) else {
                                var offset = 0
                                while (offset < converted.size) {
                                    if (cancelled()) throw CancellationException()
                                    val end = minOf(converted.size, offset + 8192)
                                    emit(converted.copyOfRange(offset, end))
                                    offset = end
                                }
                            }
                            frames += converted.size / 2
                        }
                        lastProgress = System.nanoTime()
                        if (ended) {
                            require(frames > 0) { "Recording decoded no frames" }
                            return
                        }
                    }
                }
                check(System.nanoTime() - lastProgress < 15_000_000_000L) { "MP3 decoder stalled" }
            }
            throw CancellationException()
        } finally {
            try { codec?.stop() } catch (_: Exception) { }
            codec?.release()
            extractor.release()
        }
    }
}
