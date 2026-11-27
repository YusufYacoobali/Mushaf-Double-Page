import AVFoundation

/// Core Audio decodes original MP3 packets and their declared packet-table
/// priming/remainder. No guessed delay or amplitude trimming is applied.
enum PcmDecoder {
    static func suffix(_ input: AVAudioPCMBuffer, dropping: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let count = input.frameLength - dropping
        let result = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: count)!
        result.frameLength = count
        for channel in 0..<Int(input.format.channelCount) {
            result.floatChannelData![channel].update(from: input.floatChannelData![channel].advanced(by: Int(dropping)), count: Int(count))
        }
        return result
    }
    static func decode(path: String, cancelled: @escaping () -> Bool, emit: (AVAudioPCMBuffer) -> Void) throws {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path), commonFormat: .pcmFormatFloat32, interleaved: false)
        let source = file.processingFormat
        guard source.channelCount == 1 || source.channelCount == 2 else { throw PcmError.invalidRecording }
        let target = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        if source.sampleRate == target.sampleRate && source.channelCount == target.channelCount {
            // A compressed file can report an estimated length. A successful
            // zero-frame read is EOF even if that estimate is larger.
            while !cancelled() {
                let ended: Bool = try autoreleasepool {
                    let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 4096)!
                    try file.read(into: buffer, frameCount: 4096)
                    guard buffer.frameLength > 0 else { return true }
                    emit(buffer)
                    return false
                }
                if ended { return }
            }
            return
        }
        guard let converter = AVAudioConverter(from: source, to: target) else { throw PcmError.invalidRecording }
        converter.primeMethod = .none
        var readError: Error?
        while !cancelled() {
            let ended: Bool = try autoreleasepool {
                let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4096)!
                var error: NSError?
                let status = converter.convert(to: output, error: &error) { requested, status in
                    if cancelled() { status.pointee = .endOfStream; return nil }
                    do {
                        let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: min(requested, 4096))!
                        try file.read(into: input, frameCount: input.frameCapacity)
                        status.pointee = input.frameLength > 0 ? .haveData : .endOfStream
                        return input.frameLength > 0 ? input : nil
                    } catch {
                        readError = error; status.pointee = .endOfStream; return nil
                    }
                }
                if let error = readError { throw error }
                if let error = error { throw error }
                if output.frameLength > 0 { emit(output) }
                if status == .error { throw PcmError.invalidRecording }
                return status == .endOfStream
            }
            if ended { return }
        }
    }
}
