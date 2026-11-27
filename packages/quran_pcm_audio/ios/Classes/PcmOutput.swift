import AVFoundation

enum PcmError: Error { case invalidCommand, invalidRecording, emptyRecording, engineUnavailable }
private struct TimelineRow {
    let id: String
    let start: Int64
    var decoded: Int64 = 0
    var end: Int64?
}

/// The decoder and the serial output queue are independent of the platform UI
/// thread. Only bounded state copies cross to Flutter's main-thread event sink.
final class PcmOutput {
    let generation: Int64
    private let audio: PcmAudioQueue
    private let condition = NSCondition()
    private let worker = DispatchQueue(label: "quran.pcm.decode", qos: .userInitiated)
    private let engine: AVAudioEngine
    private let player: AVAudioPlayerNode
    private let capacity: Int64
    private let seek: Int64
    private var timer: DispatchSourceTimer? // audio queue only
    private var sources: [[String: String]] = []
    private var rows: [TimelineRow] = []
    private var clock = PcmFrameClock() // protected by condition, including producer backpressure
    private var decoded: Int64 = 0
    private var cancelled = false
    private var finished = false
    private var decodedAll = false
    private var decoding: String?
    private var playing = false
    private var starved = false
    private var underruns = 0
    private var scheduledBuffers = 0
    private var completedBuffers = 0
    private var scheduleWaitMaxMs = 0.0
    private var minBufferedFrames: Int64?
    private var state = "loading"
    private var failure: String?
    private var cache: [String: [AVAudioPCMBuffer]] = [:] // decode worker only
    private var cacheOrder: [String] = []
    private var cachedFrames: Int64 = 0
    private var routeObserver: NSObjectProtocol?
    private var configurationObserver: NSObjectProtocol?

    init(generation: Int64, seconds: Int, seek: Int64) throws {
        guard (1...15).contains(seconds) else { throw PcmError.invalidCommand }
        self.generation = generation
        capacity = Int64(seconds) * 44100
        self.seek = max(0, seek)
        let audio = PcmAudioQueue()
        let nodes = audio.sync { () -> (AVAudioEngine, AVAudioPlayerNode) in
            let engine = AVAudioEngine(), player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode,
                format: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!)
            return (engine, player)
        }
        self.audio = audio; engine = nodes.0; player = nodes.1
        // No competing audio session/focus owner. Observe on the posting thread,
        // then serialize handling with playback instead of waiting for UIKit.
        routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.audio.async { [weak self] in self?.checkOutput() }
        }
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.audio.async { [weak self] in self?.checkOutput(invalidated: true) }
        }
    }
    deinit {
        timer?.cancel()
        if let observer = routeObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = configurationObserver { NotificationCenter.default.removeObserver(observer) }
    }
    private func checkOutput(invalidated: Bool = false) {
        let running = engine.isRunning
        condition.lock()
        let broken = !cancelled && ((invalidated && clock.scheduled > clock.played) || (playing && !running))
        condition.unlock()
        if broken { fail("Audio route invalidated the continuous engine") }
    }
    func enqueue(_ source: [String: String]) throws {
        condition.lock(); defer { condition.unlock() }
        guard !cancelled, !finished, sources.count + rows.count < 6,
              let id = source["id"], !id.isEmpty, let path = source["path"], path.hasPrefix("/") else { throw PcmError.invalidCommand }
        sources.append(source)
        condition.broadcast()
    }
    func finish() {
        condition.lock(); finished = true; condition.broadcast(); condition.unlock()
    }
    func remove(_ ids: [String]) {
        condition.lock(); defer { condition.unlock() }
        rows.removeAll { ids.contains($0.id) && ($0.end ?? Int64.max) <= clock.played }
    }
    func start() { worker.async { [weak self] in self?.produce() } }

    func setPlaying(_ value: Bool) throws {
        try audio.sync {
            updateClock()
            condition.lock()
            let valid = !cancelled && failure == nil
            condition.unlock()
            guard valid else { if value { throw PcmError.engineUnavailable }; return }
            if value {
                if !engine.isRunning { try engine.start() }
                player.play()
            } else { player.pause() }
            condition.lock(); playing = value; condition.broadcast(); condition.unlock()
            timer?.cancel(); timer = nil
            if value { timer = audio.timer { [weak self] in self?.poll() } }
            poll()
        }
    }

    private func produce() {
        var first = true
        do {
            while true {
                condition.lock()
                while sources.isEmpty && !finished && !cancelled && failure == nil { condition.wait() }
                if cancelled || failure != nil { condition.unlock(); return }
                if sources.isEmpty {
                    decodedAll = true
                    condition.unlock()
                    audio.async { [weak self] in self?.poll() }
                    return
                }
                let source = sources.removeFirst(), id = source["id"]!, path = source["path"]!
                decoding = id
                rows.append(TimelineRow(id: id, start: decoded))
                condition.unlock()
                var remaining = first ? seek : 0
                first = false
                var count: Int64 = 0
                let append: (AVAudioPCMBuffer) -> Void = { buffer in
                    let frames = Int64(buffer.frameLength), drop = min(remaining, Int64(buffer.frameLength))
                    remaining -= drop
                    count += frames
                    self.condition.lock()
                    while self.clock.scheduled - self.clock.played + frames - drop > self.capacity && !self.cancelled && self.failure == nil { self.condition.wait() }
                    if self.cancelled || self.failure != nil { self.condition.unlock(); return }
                    let start = self.decoded + drop
                    self.decoded += frames
                    if let row = self.rows.firstIndex(where: { $0.id == id }) { self.rows[row].decoded += frames }
                    if drop > 0 { self.clock.skip(to: start, frames: drop) }
                    self.condition.unlock()
                    if frames == drop { return }
                    let output = drop == 0 ? buffer : PcmDecoder.suffix(buffer, dropping: AVAudioFrameCount(drop))
                    let ready = DispatchTime.now().uptimeNanoseconds
                    self.audio.sync {
                        self.condition.lock(); let valid = !self.cancelled && self.failure == nil; self.condition.unlock()
                        if !valid { return }
                        let nodeTime = self.player.lastRenderTime.flatMap { self.player.playerTime(forNodeTime: $0) }?.sampleTime ?? 0
                        let safety = Int64(AVAudioSession.sharedInstance().ioBufferDuration * 44100)
                        self.condition.lock()
                        let span = self.clock.append(start: start, frames: frames - drop, nodeTime: nodeTime, safety: self.playing ? safety : 0)
                        self.scheduledBuffers += 1
                        self.scheduleWaitMaxMs = max(self.scheduleWaitMaxMs, Double(DispatchTime.now().uptimeNanoseconds - ready) / 1_000_000)
                        self.condition.unlock()
                        self.player.scheduleBuffer(output, at: AVAudioTime(sampleTime: span.nodeStart, atRate: 44100), options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                            self?.audio.async { [weak self] in
                                guard let self = self else { return }
                                self.condition.lock()
                                if !self.cancelled {
                                    self.clock.complete(span, playing: self.playing)
                                    self.completedBuffers += 1
                                }
                                self.condition.broadcast(); self.condition.unlock()
                                self.poll()
                            }
                        }
                        self.poll()
                    }
                }
                if let reusable = cache[path] {
                    cacheOrder.removeAll { $0 == path }; cacheOrder.append(path)
                    for buffer in reusable { append(buffer) }
                } else {
                    var reusable: [AVAudioPCMBuffer] = [], reusableFrames: Int64 = 0
                    try PcmDecoder.decode(path: path, cancelled: { [weak self] in
                        guard let self = self else { return true }
                        self.condition.lock(); defer { self.condition.unlock() }
                        return self.cancelled || self.failure != nil
                    }) { buffer in
                        reusableFrames += Int64(buffer.frameLength)
                        if reusableFrames <= 88200 { reusable.append(buffer) } else { reusable.removeAll() }
                        append(buffer)
                    }
                    if reusableFrames <= 88200 {
                        while !cacheOrder.isEmpty && (cachedFrames + reusableFrames > 88200 || cacheOrder.count >= 8) {
                            let oldest = cacheOrder.removeFirst()
                            cachedFrames -= (cache.removeValue(forKey: oldest) ?? []).reduce(0) { $0 + Int64($1.frameLength) }
                        }
                        cache[path] = reusable; cacheOrder.append(path); cachedFrames += reusableFrames
                    }
                }
                condition.lock()
                if cancelled || failure != nil { condition.unlock(); return }
                if let row = rows.firstIndex(where: { $0.id == id }) { rows[row].end = decoded }
                decoding = nil
                condition.unlock()
                if count == 0 { throw PcmError.emptyRecording }
            }
        } catch { audio.async { [weak self] in self?.fail(String(describing: error)) } }
    }

    private func updateClock() {
        condition.lock(); let active = playing && !cancelled && failure == nil; condition.unlock()
        guard active, let renderTime = player.lastRenderTime,
              let time = player.playerTime(forNodeTime: renderTime) else { return }
        let session = AVAudioSession.sharedInstance()
        let latency = player.outputPresentationLatency > 0 ? player.outputPresentationLatency : session.outputLatency + session.ioBufferDuration
        condition.lock()
        if !cancelled { clock.advance(renderedNodeFrame: time.sampleTime - Int64(latency * 44100)) }
        condition.broadcast(); condition.unlock()
    }
    private func poll() {
        updateClock()
        condition.lock()
        let buffered = max(0, clock.scheduled - clock.played)
        let buffering = playing && clock.renderedAny && buffered == 0 && !decodedAll && !cancelled && failure == nil
        var log: String?
        if buffering && !starved {
            underruns += 1
            log = "[QuranPCM] underrun generation=\(generation) count=\(underruns) rendered=\(clock.played) buffered=\(buffered) queued=\(sources.count) decoding=\(decoding != nil) scheduleWaitMaxMs=\(scheduleWaitMaxMs)"
        } else if starved && !buffering && playing && !cancelled && failure == nil {
            log = "[QuranPCM] resumed generation=\(generation) rendered=\(clock.played) buffered=\(buffered)"
        }
        starved = buffering
        if playing && clock.renderedAny { minBufferedFrames = min(minBufferedFrames ?? buffered, buffered) }
        state = cancelled ? "idle" : (decodedAll && clock.played >= decoded ? "completed" : (buffering ? "buffering" : (clock.scheduled == 0 || (playing && !clock.renderedAny) ? "loading" : "ready")))
        let terminal = cancelled || failure != nil || state == "completed"
        condition.broadcast(); condition.unlock()
        if let log = log { NSLog("%@", log) }
        if terminal { timer?.cancel(); timer = nil }
    }
    private func fail(_ error: String) {
        updateClock() // Preserve the latest rendered occurrence before freezing it.
        condition.lock()
        if !cancelled && failure == nil { failure = error }
        condition.broadcast(); condition.unlock()
        player.pause()
        poll()
    }
    func snapshot() -> [String: Any] {
        condition.lock(); defer { condition.unlock() }
        var result: [String: Any] = ["generation": generation, "frames": clock.played,
            "bufferedFrames": clock.scheduled, "scheduledFrames": clock.scheduled, "decodedFrames": decoded, "state": state, "underruns": underruns,
            "pcmBufferedFrames": max(0, clock.scheduled - clock.played), "pcmCapacityFrames": capacity,
            "scheduledBuffers": scheduledBuffers, "completedBuffers": completedBuffers,
            "scheduleWaitMaxMs": scheduleWaitMaxMs, "queuedRecordings": sources.count,
            "decodingOccurrence": decoding as Any? ?? NSNull(),
            "rows": rows.map { row -> [String: Any] in
                var value: [String: Any] = ["id": row.id, "start": row.start, "decoded": row.decoded]
                if let end = row.end { value["end"] = end }
                return value
            }]
        if let minimum = minBufferedFrames { result["minBufferedFrames"] = minimum }
        if let error = failure { result["error"] = error }
        return result
    }
    func requestCancellation() {
        condition.lock(); cancelled = true; condition.broadcast(); condition.unlock()
    }
    func cancel() {
        requestCancellation() // Wake backpressure before waiting for the output queue.
        audio.sync {
            timer?.cancel(); timer = nil
            condition.lock(); playing = false; sources.removeAll(); state = "idle"; condition.unlock()
            player.stop()
            engine.stop()
        }
    }
}
