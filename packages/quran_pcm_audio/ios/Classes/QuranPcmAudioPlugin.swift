import AVFoundation
import Flutter

public final class QuranPcmAudioPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    // Flutter callbacks/telemetry stay on main; lifecycle commands run separately.
    // The audio render queue never waits for either Flutter or this command queue.
    private let commands = DispatchQueue(label: "quran.pcm.commands", qos: .userInitiated)
    private let probes = DispatchQueue(label: "quran.pcm.probe", qos: .userInitiated)
    private let referenceLock = NSLock()
    private var output: PcmOutput?
    private var attached = true
    private var sink: FlutterEventSink?
    private var timer: Timer?

    private var currentOutput: PcmOutput? {
        referenceLock.lock(); defer { referenceLock.unlock() }
        return output
    }
    private func install(_ next: PcmOutput?) -> Bool {
        referenceLock.lock(); defer { referenceLock.unlock() }
        guard attached else { return false }
        output = next
        return true
    }
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = QuranPcmAudioPlugin()
        registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(name: "quran/pcm", binaryMessenger: registrar.messenger()))
        FlutterEventChannel(name: "quran/pcm/events", binaryMessenger: registrar.messenger()).setStreamHandler(instance)
    }
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        referenceLock.lock()
        attached = false
        let previous = output
        output = nil
        referenceLock.unlock()
        previous?.requestCancellation()
        commands.async { previous?.cancel() }
        timer?.invalidate()
        sink = nil
    }
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        if currentOutput != nil { startTimer() }
        return nil
    }
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let output = self.currentOutput else { return }
            // Copy already-maintained state; no engine work or clock polling here.
            self.sink?(output.snapshot())
        }
    }
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        timer?.invalidate()
        sink = nil
        return nil
    }
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "needsStereoCorrection", let args = call.arguments as? [String: Any], let path = args["path"] as? String {
            probes.async {
                let restore = StereoPolarity.needsCorrection(url: URL(fileURLWithPath: path), cancelled: { false })
                DispatchQueue.main.async { result(restore) }
            }
            return
        }
        guard let args = call.arguments as? [String: Any], let number = args["generation"] as? NSNumber else {
            result(FlutterError(code: "pcm", message: "Invalid command", details: nil)); return
        }
        let generation = number.int64Value
        let method = call.method
        commands.async {
            do {
                self.referenceLock.lock(); let active = self.attached; self.referenceLock.unlock()
                guard active else { throw PcmError.engineUnavailable }
                if method == "prepare" {
                    self.currentOutput?.cancel()
                    guard let sources = args["sources"] as? [[String: String]], !sources.isEmpty, sources.count <= 6,
                          let seconds = args["bufferSeconds"] as? Int, (1...15).contains(seconds) else { throw PcmError.invalidCommand }
                    let next = try PcmOutput(generation: generation, seconds: seconds, seek: (args["seekFrames"] as? NSNumber)?.int64Value ?? 0)
                    for source in sources { try next.enqueue(source) }
                    guard self.install(next) else { next.cancel(); throw PcmError.engineUnavailable }
                    next.start()
                    DispatchQueue.main.async {
                        if self.currentOutput === next && self.sink != nil { self.startTimer() }
                    }
                } else if method == "stop" {
                    if generation >= (self.currentOutput?.generation ?? 0) {
                        self.currentOutput?.cancel()
                        _ = self.install(nil)
                        DispatchQueue.main.async {
                            if self.currentOutput == nil { self.timer?.invalidate() }
                        }
                    }
                } else if let current = self.currentOutput, current.generation == generation {
                    switch method {
                    case "snapshot":
                        let snapshot = current.snapshot()
                        DispatchQueue.main.async { result(snapshot) }; return
                    case "enqueue":
                        guard let id = args["id"] as? String, let path = args["path"] as? String else { throw PcmError.invalidCommand }
                        var source = ["id": id, "path": path]
                        source["polarity"] = args["polarity"] as? String
                        try current.enqueue(source)
                    case "play": try current.setPlaying(true)
                    case "pause": try current.setPlaying(false)
                    case "finish": current.finish()
                    case "remove": current.remove(args["ids"] as? [String] ?? [])
                    default: DispatchQueue.main.async { result(FlutterMethodNotImplemented) }; return
                    }
                }
                DispatchQueue.main.async { result(nil) }
            } catch {
                DispatchQueue.main.async { result(FlutterError(code: "pcm", message: String(describing: error), details: nil)) }
            }
        }
    }
}
