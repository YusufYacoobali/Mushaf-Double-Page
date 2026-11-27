package com.quran.pcm

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTimestamp
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque
import java.util.concurrent.CancellationException
import kotlin.concurrent.thread

/** Engine-scoped, independent of Activity lifetime. audio_service is the sole
 * foreground media service; audio_session remains the sole audio focus owner. */
class QuranPcmAudioPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var probes: java.util.concurrent.ExecutorService
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var engine: PcmOutput? = null
    private val tick = object : Runnable {
        override fun run() {
            engine?.let { sink?.success(it.snapshot()) }
            if (engine != null && sink != null) main.postDelayed(this, 100)
        }
    }
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        probes = java.util.concurrent.Executors.newSingleThreadExecutor()
        methods = MethodChannel(binding.binaryMessenger, "quran/pcm")
        events = EventChannel(binding.binaryMessenger, "quran/pcm/events")
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        probes.shutdownNow()
        engine?.cancel()
        engine = null
        main.removeCallbacks(tick)
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
    }
    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        sink = eventSink
        if (engine != null) main.post(tick)
    }
    override fun onCancel(arguments: Any?) {
        sink = null
        main.removeCallbacks(tick)
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (call.method == "needsStereoCorrection") {
                val path = requireNotNull(call.argument<String>("path"))
                probes.execute {
                    val restore = try {
                        Mp3Decoder.needsCorrection(path) { Thread.currentThread().isInterrupted }
                    } catch (_: CancellationException) { false }
                    main.post { result.success(restore) }
                }
                return
            }
            val generation = call.argument<Number>("generation")!!.toLong()
            if (call.method == "prepare") {
                engine?.cancel()
                val seconds = call.argument<Int>("bufferSeconds")!!
                require(seconds in 1..15)
                val sources = call.argument<List<Map<String, String>>>("sources")!!
                require(sources.isNotEmpty() && sources.size <= 6)
                engine = PcmOutput(generation, seconds, call.argument<Number>("seekFrames")!!.toLong())
                sources.forEach { engine!!.enqueue(it.getValue("id"), it.getValue("path"), it["polarity"] == "inverted") }
                engine!!.start()
                main.removeCallbacks(tick)
                if (sink != null) main.post(tick)
            } else if (call.method == "stop") {
                if (generation >= (engine?.generation ?: 0)) {
                    engine?.cancel()
                    engine = null
                    main.removeCallbacks(tick)
                }
            } else {
                val current = engine
                if (current != null && current.generation == generation) {
                    when (call.method) {
                        "snapshot" -> { result.success(current.snapshot()); return }
                        "enqueue" -> current.enqueue(call.argument<String>("id")!!, call.argument<String>("path")!!, call.argument<String>("polarity") == "inverted")
                        "finish" -> current.finish()
                        "play" -> current.setPlaying(true)
                        "pause" -> current.setPlaying(false)
                        "remove" -> current.remove(call.argument<List<String>>("ids")!!)
                        else -> { result.notImplemented(); return }
                    }
                }
            }
            result.success(null)
        } catch (error: Exception) {
            result.error("pcm", error.message, null)
        }
    }
}

private data class Source(val id: String, val path: String, val invert: Boolean)
private data class Row(val id: String, val start: Long, var decoded: Long = 0, var end: Long? = null)

/** Two non-real-time workers with an eight-second bounded FIFO. The platform's
 * real-time audio thread only consumes AudioTrack's small hardware-facing ring.
 * One AudioTrack persists across recordings, repeats, format changes and stalls. */
internal class PcmOutput(val generation: Long, seconds: Int, private val seek: Long) {
    private val lock = Object()
    private val trackLock = Object()
    private val sources = ArrayDeque<Source>()
    private val pcm = ArrayDeque<ShortArray>()
    private val cache = PcmCache()
    private val rows = ArrayList<Row>()
    private val capacity = seconds * 44100
    private var queuedFrames = 0
    private var decoded = 0L
    private var written = 0L
    private var discarded = 0L
    private var complete = false
    private var decodedAll = false
    @Volatile private var cancelled = false
    @Volatile private var playing = false
    @Volatile private var failure: String? = null
    private var track: AudioTrack? = null
    private var headWrap = 0L
    private var lastHead = 0L
    private var lastPresented = 0L
    private val timestamp = AudioTimestamp()

    fun enqueue(id: String, path: String, invert: Boolean = false) = synchronized(lock) {
        require(!complete && sources.size + rows.size < 6) { "Native recording queue overflow" }
        require(path.startsWith("/") && id.isNotEmpty())
        sources.add(Source(id, path, invert))
        lock.notifyAll()
    }
    fun finish() = synchronized(lock) { complete = true; lock.notifyAll() }
    fun remove(ids: List<String>) = synchronized(lock) {
        // The controller only prunes consumed occurrences. Never remove future
        // audio already decoded into the FIFO, which could omit recitation.
        rows.removeAll { it.id in ids && it.end != null && it.end!! <= lastPresented }
    }
    fun start() {
        thread(name = "Quran MP3 decoder") { protect { produce() } }
        thread(name = "Quran PCM writer") { protect { consume() } }
    }
    private fun protect(action: () -> Unit) {
        try { action() } catch (error: Exception) {
            if (!cancelled && error !is CancellationException) {
                failure = "${error.javaClass.simpleName}: ${error.message}"
                synchronized(trackLock) { track?.pause() }
                synchronized(lock) { lock.notifyAll() }
            }
        }
    }
    private fun produce() {
        var first = true
        while (!cancelled && failure == null) {
            val source = synchronized(lock) {
                while (sources.isEmpty() && !complete && !cancelled && failure == null) lock.wait()
                if (cancelled || failure != null) return
                if (sources.isEmpty()) {
                    decodedAll = true
                    lock.notifyAll()
                    return
                }
                sources.removeFirst()
            }
            val row = synchronized(lock) { Row(source.id, decoded).also { rows.add(it) } }
            var remaining = if (first) seek.coerceAtLeast(0) else 0L
            first = false
            val append: (ShortArray) -> Unit = { samples ->
                val frames = samples.size / 2
                val drop = minOf(remaining, frames.toLong()).toInt()
                remaining -= drop
                val audible = if (drop == 0) samples else samples.copyOfRange(drop * 2, samples.size)
                synchronized(lock) {
                    while (queuedFrames + audible.size / 2 > capacity && !cancelled && failure == null) lock.wait()
                    if (cancelled || failure != null) throw CancellationException()
                    row.decoded += frames
                    decoded += frames
                    discarded += drop
                    if (audible.isNotEmpty()) {
                        pcm.add(audible)
                        queuedFrames += audible.size / 2
                    }
                    lock.notifyAll()
                }
            }
            val cached = cache[source.path]
            if (cached != null) {
                cached.forEach(append)
            } else {
                val reusable = ArrayList<ShortArray>()
                var reusableFrames = 0
                Mp3Decoder.decode(source.path, { cancelled || failure != null }, source.invert) { samples ->
                    reusableFrames += samples.size / 2
                    if (reusableFrames <= 88200) reusable.add(samples) else reusable.clear()
                    append(samples)
                }
                if (reusableFrames <= 88200) cache.put(source.path, reusable)
            }
            synchronized(lock) { row.end = decoded; lock.notifyAll() }
        }
    }
    private fun consume() {
        val minimum = AudioTrack.getMinBufferSize(44100, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
        require(minimum > 0) { "PCM output unsupported" }
        val output = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAudioFormat(AudioFormat.Builder().setSampleRate(44100)
                .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(maxOf(minimum * 2, 4410 * 4))
            .build()
        synchronized(trackLock) {
            if (cancelled) { output.release(); return }
            check(output.state == AudioTrack.STATE_INITIALIZED)
            track = output
            if (Build.VERSION.SDK_INT >= 31) output.setStartThresholdInFrames(minOf(4410, output.bufferSizeInFrames))
            if (playing) output.play()
        }
        while (!cancelled && failure == null) {
            val samples = synchronized(lock) {
                while (pcm.isEmpty() && !decodedAll && !cancelled && failure == null) lock.wait()
                if (cancelled || failure != null || pcm.isEmpty()) return
                pcm.removeFirst().also { queuedFrames -= it.size / 2; lock.notifyAll() }
            }
            var offset = 0
            while (offset < samples.size && !cancelled && failure == null) {
                val count = synchronized(trackLock) {
                    if (cancelled) return
                    output.write(samples, offset, samples.size - offset, AudioTrack.WRITE_NON_BLOCKING)
                }
                check(count >= 0) { "AudioTrack write failed: $count" }
                if (count == 0) {
                    synchronized(lock) { if (!cancelled) lock.wait(10) }
                } else {
                    offset += count
                    synchronized(lock) { written += count / 2 }
                }
            }
        }
    }
    fun setPlaying(value: Boolean) {
        synchronized(trackLock) {
            track?.let {
                if (value) it.play() else {
                    presented(it)
                    it.pause()
                }
            }
            playing = value
        }
        synchronized(lock) { lock.notifyAll() }
    }
    private fun presented(output: AudioTrack): Long {
        val head = output.playbackHeadPosition.toLong() and 0xffffffffL
        if (head < lastHead) headWrap += 1L shl 32
        lastHead = head
        var frames = headWrap + head
        // Timestamp frame/time pair measures presentation, rather than samples
        // submitted to the writer. Cap extrapolation at the frames written.
        if (playing && output.getTimestamp(timestamp)) {
            val delta = (System.nanoTime() - timestamp.nanoTime).coerceAtLeast(0)
            // A timestamp can stop advancing during a real underrun. Never
            // extrapolate through that missing wall time into newly queued data.
            if (delta <= 200_000_000L) frames = minOf(frames, timestamp.framePosition + delta * 44100 / 1_000_000_000)
        }
        val absolute = synchronized(lock) { discarded + frames.coerceAtMost(written) }
        lastPresented = maxOf(lastPresented, absolute)
        return lastPresented
    }
    fun snapshot(): Map<String, Any?> {
        val frame = synchronized(trackLock) {
            if (playing) track?.let { presented(it) } ?: discarded else maxOf(lastPresented, discarded)
        }
        val underruns = synchronized(trackLock) { if (Build.VERSION.SDK_INT >= 24) track?.underrunCount ?: 0 else 0 }
        return synchronized(lock) {
            val state = when {
                decodedAll && frame >= decoded && pcm.isEmpty() -> "completed"
                frame >= decoded && playing -> "buffering"
                written == 0L || (playing && frame <= discarded) -> "loading"
                else -> "ready"
            }
            mapOf("generation" to generation, "frames" to frame, "bufferedFrames" to decoded,
                "scheduledFrames" to written + discarded, "decodedFrames" to decoded, "queuedRecordings" to sources.size,
                "state" to state, "underruns" to underruns, "error" to failure,
                "pcmBufferedFrames" to maxOf(0, decoded - frame), "pcmCapacityFrames" to capacity,
                "rows" to rows.map { mapOf("id" to it.id, "start" to it.start, "end" to it.end, "decoded" to it.decoded) })
        }
    }
    fun cancel() {
        cancelled = true
        playing = false
        synchronized(lock) { pcm.clear(); sources.clear(); lock.notifyAll() }
        synchronized(trackLock) {
            track?.let {
                try { it.pause(); it.flush(); it.stop() } finally { it.release() }
            }
            track = null
        }
    }
}
