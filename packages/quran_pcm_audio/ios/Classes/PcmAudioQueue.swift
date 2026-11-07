import Foundation

/// All engine/player access belongs here. Reentrant sync is safe, and neither
/// buffer scheduling, playback completions nor the presentation clock uses main.
final class PcmAudioQueue {
    private let queue = DispatchQueue(label: "quran.pcm.output", qos: .userInitiated)
    private let key = DispatchSpecificKey<Bool>()

    init() { queue.setSpecific(key: key, value: true) }
    func sync<T>(_ action: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: key) == true { return try action() }
        return try queue.sync(execute: action)
    }
    func async(_ action: @escaping () -> Void) { queue.async { action() } }
    func timer(_ action: @escaping () -> Void) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(5))
        timer.setEventHandler(handler: action)
        timer.resume()
        return timer
    }
}
