import AVFoundation
import Flutter

public final class QuranPcmAudioPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var output: PcmOutput?
    private var sink: FlutterEventSink?
    private var timer: Timer?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = QuranPcmAudioPlugin()
        registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(name: "quran/pcm", binaryMessenger: registrar.messenger()))
        FlutterEventChannel(name: "quran/pcm/events", binaryMessenger: registrar.messenger()).setStreamHandler(instance)
    }
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        output?.cancel()
        timer?.invalidate()
        sink = nil
    }
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        if output != nil { startTimer() }
        return nil
    }
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let output = self.output else { return }
            self.sink?(output.snapshot())
        }
    }
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        timer?.invalidate()
        sink = nil
        return nil
    }
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            guard let args = call.arguments as? [String: Any], let generation = args["generation"] as? NSNumber else {
                throw PcmError.invalidCommand
            }
            if call.method == "prepare" {
                output?.cancel()
                guard let sources = args["sources"] as? [[String: String]], !sources.isEmpty, sources.count <= 6,
                      let seconds = args["bufferSeconds"] as? Int, (1...15).contains(seconds) else { throw PcmError.invalidCommand }
                let next = try PcmOutput(generation: generation.int64Value, seconds: seconds, seek: (args["seekFrames"] as? NSNumber)?.int64Value ?? 0)
                output = next
                for source in sources { try next.enqueue(source) }
                next.start()
                if sink != nil { startTimer() }
            } else if call.method == "stop" {
                if generation.int64Value >= (output?.generation ?? 0) {
                    output?.cancel()
                    output = nil
                    timer?.invalidate()
                }
            } else if let current = output, current.generation == generation.int64Value {
                switch call.method {
                case "enqueue":
                    guard let id = args["id"] as? String, let path = args["path"] as? String else { throw PcmError.invalidCommand }
                    try current.enqueue(["id": id, "path": path])
                case "play": try current.setPlaying(true)
                case "pause": try current.setPlaying(false)
                case "finish": current.finish()
                case "remove": current.remove(args["ids"] as? [String] ?? [])
                default: result(FlutterMethodNotImplemented); return
                }
            }
            result(nil)
        } catch {
            result(FlutterError(code: "pcm", message: String(describing: error), details: nil))
        }
    }
}

enum PcmError: Error { case invalidCommand, invalidRecording, emptyRecording, engineUnavailable }
private struct TimelineRow {
    let id: String
    let start: Int64
    var decoded: Int64 = 0
    var end: Int64?
}
private struct ScheduledChunk {
    let streamStart: Int64
    let nodeStart: Int64
    let frames: Int64
}

/// The serial worker only decodes; AVAudioPlayerNode owns real-time rendering.
/// Scheduled buffers, including the node's retained references, share one budget.
final class PcmOutput {
    let generation: Int64
    private let condition = NSCondition()
    private let worker = DispatchQueue(label: "quran.pcm.decode", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    private let capacity: Int64
    private let seek: Int64
    private var sources: [[String: String]] = []
    private var cache: [String: [AVAudioPCMBuffer]] = [:] // decode worker only
    private var cacheOrder: [String] = []
    private var cachedFrames: Int64 = 0
    private var rows: [TimelineRow] = []
    private var chunks: [ScheduledChunk] = [] // main queue only
    private var decoded: Int64 = 0
    private var scheduled: Int64 = 0
    private var played: Int64 = 0
    private var nodeEnd: Int64 = 0
    private var cancelled = false
    private var finished = false
    private var decodedAll = false
    private var playing = false
    private var renderedAny = false
    private var starved = false
    private var underruns = 0
    private var failure: String?
    private var routeObserver: NSObjectProtocol?
    private var configurationObserver: NSObjectProtocol?

    init(generation: Int64, seconds: Int, seek: Int64) throws {
        self.generation = generation
        self.capacity = Int64(seconds) * 44100
        self.seek = max(0, seek)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        // Session category, focus and interruptions belong to QuranAudioHandler.
        // Do not activate a competing AVAudioSession here.
        routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.checkOutput()
        }
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.checkOutput(invalidated: true)
        }
    }
    deinit {
        if let observer = routeObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = configurationObserver { NotificationCenter.default.removeObserver(observer) }
    }
    private func checkOutput(invalidated: Bool = false) {
        // A route may invalidate scheduled buffers. Never silently lose those
        // samples: stop and let the controller restart the current ayah safely.
        condition.lock()
        if !cancelled && ((invalidated && scheduled > played) || (playing && !engine.isRunning)) {
            failure = "Audio route invalidated the continuous engine"
            player.pause()
        }
        condition.broadcast()
        condition.unlock()
    }
    func enqueue(_ source: [String: String]) throws {
        condition.lock(); defer { condition.unlock() }
        guard !finished, sources.count + rows.count < 6,
              let id = source["id"], !id.isEmpty, let path = source["path"], path.hasPrefix("/") else { throw PcmError.invalidCommand }
        sources.append(source)
        condition.broadcast()
    }
    func finish() {
        condition.lock(); finished = true; condition.broadcast(); condition.unlock()
    }
    func remove(_ ids: [String]) {
        condition.lock(); defer { condition.unlock() }
        rows.removeAll { ids.contains($0.id) && ($0.end ?? Int64.max) <= played }
    }
    func start() {
        worker.async { [weak self] in self?.produce() }
    }
    func setPlaying(_ value: Bool) throws {
        if !value { updateClock() }
        condition.lock(); playing = value; condition.unlock()
        if value {
            if !engine.isRunning { try engine.start() }
            player.play()
        } else { player.pause() }
    }
    private func produce() {
        var first = true
        do {
            while true {
                condition.lock()
                while sources.isEmpty && !finished && !cancelled && failure == nil { condition.wait() }
                if cancelled || failure != nil { condition.unlock(); return }
                if sources.isEmpty { decodedAll = true; condition.unlock(); return }
                let source = sources.removeFirst()
                let id = source["id"]!
                rows.append(TimelineRow(id: id, start: decoded))
                condition.unlock()
                var remaining = first ? seek : 0
                first = false
                var count: Int64 = 0
                let path = source["path"]!
                let append: (AVAudioPCMBuffer) -> Void = { buffer in
                    let frames = Int64(buffer.frameLength)
                    let drop = min(remaining, frames)
                    remaining -= drop
                    count += frames
                    self.condition.lock()
                    while self.scheduled - self.played + frames - drop > self.capacity && !self.cancelled && self.failure == nil { self.condition.wait() }
                    if self.cancelled || self.failure != nil { self.condition.unlock(); return }
                    let start = self.decoded + drop
                    self.decoded += frames
                    if let row = self.rows.firstIndex(where: { $0.id == id }) { self.rows[row].decoded += frames }
                    self.played = max(self.played, drop > 0 ? start : self.played)
                    self.scheduled += drop
                    self.condition.unlock()
                    if frames == drop { return }
                    let output = drop == 0 ? buffer : PcmDecoder.suffix(buffer, dropping: AVAudioFrameCount(drop))
                    DispatchQueue.main.sync {
                        self.condition.lock(); let valid = !self.cancelled && self.failure == nil; self.condition.unlock()
                        if !valid { return }
                        let currentNodeTime = self.player.lastRenderTime.flatMap { self.player.playerTime(forNodeTime: $0) }?.sampleTime ?? 0
                        let nodeStart = max(self.nodeEnd, currentNodeTime + (self.chunks.isEmpty && self.playing ? Int64(AVAudioSession.sharedInstance().ioBufferDuration * 44100) : 0))
                        let chunk = ScheduledChunk(streamStart: start, nodeStart: nodeStart, frames: frames - drop)
                        self.chunks.append(chunk)
                        self.nodeEnd = nodeStart + chunk.frames
                        self.condition.lock(); self.scheduled += chunk.frames; self.condition.unlock()
                        self.player.scheduleBuffer(output, at: AVAudioTime(sampleTime: nodeStart, atRate: 44100), options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
                            DispatchQueue.main.async {
                                guard let self = self else { return }
                                self.condition.lock()
                                if !self.cancelled && self.playing {
                                    self.played = max(self.played, start + chunk.frames)
                                    self.renderedAny = true
                                    self.chunks.removeAll { $0.streamStart <= start }
                                }
                                self.condition.broadcast(); self.condition.unlock()
                            }
                        }
                    }
                }
                if let reusable = cache[path] {
                    cacheOrder.removeAll { $0 == path }; cacheOrder.append(path)
                    for buffer in reusable { append(buffer) }
                } else {
                    var reusable: [AVAudioPCMBuffer] = []
                    var reusableFrames: Int64 = 0
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
                        cache[path] = reusable
                        cacheOrder.append(path)
                        cachedFrames += reusableFrames
                    }
                }
                condition.lock()
                if cancelled || failure != nil { condition.unlock(); return }
                if let row = rows.firstIndex(where: { $0.id == id }) { rows[row].end = decoded }
                condition.unlock()
                if count == 0 { throw PcmError.emptyRecording }
            }
        } catch {
            condition.lock()
            if !cancelled { failure = String(describing: error) }
            condition.broadcast(); condition.unlock()
            DispatchQueue.main.async { [weak self] in self?.player.pause() }
        }
    }
    private func updateClock() {
        guard playing, let renderTime = player.lastRenderTime,
              let time = player.playerTime(forNodeTime: renderTime) else { return }
        let session = AVAudioSession.sharedInstance()
        let latency = player.outputPresentationLatency > 0 ? player.outputPresentationLatency : session.outputLatency + session.ioBufferDuration
        let rendered = time.sampleTime - Int64(latency * 44100)
        condition.lock(); defer { condition.unlock() }
        for chunk in chunks where rendered >= chunk.nodeStart {
            played = max(played, chunk.streamStart + min(chunk.frames, rendered - chunk.nodeStart))
            if rendered > chunk.nodeStart { renderedAny = true }
        }
        condition.broadcast()
    }
    func snapshot() -> [String: Any] {
        updateClock()
        condition.lock(); defer { condition.unlock() }
        let buffering = playing && renderedAny && played >= scheduled && !decodedAll
        if buffering && !starved { underruns += 1 }
        starved = buffering
        let state = decodedAll && played >= decoded ? "completed" : (buffering ? "buffering" : (scheduled == 0 || (playing && !renderedAny) ? "loading" : "ready"))
        var result: [String: Any] = ["generation": generation, "frames": played, "bufferedFrames": scheduled, "state": state, "underruns": underruns,
            "pcmBufferedFrames": max(0, scheduled - played), "pcmCapacityFrames": capacity,
            "rows": rows.map { row -> [String: Any] in
                var value: [String: Any] = ["id": row.id, "start": row.start, "decoded": row.decoded]
                if let end = row.end { value["end"] = end }
                return value
            }]
        if let error = failure { result["error"] = error }
        return result
    }
    func cancel() {
        condition.lock(); cancelled = true; playing = false; sources.removeAll(); condition.broadcast(); condition.unlock()
        player.stop()
        engine.stop()
        chunks.removeAll()
    }
}
