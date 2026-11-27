import AVFoundation

enum StereoPolarity {
    /// Match the Android decoder's three-window test on the source channels.
    /// AVAudioFile uses normalized, non-interleaved floats.
    static func needsCorrection(url: URL, cancelled: () -> Bool) -> Bool {
        do {
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
            let format = file.processingFormat
            let rate = format.sampleRate
            guard file.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatMPEGLayer3,
                  format.channelCount == 2, Double(file.length) >= 0.9 * rate else { return false }
            let warmup = Int(rate * 0.080)
            let window = Int(rate * 0.400)
            let capacity = AVAudioFrameCount(warmup + window)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return false }
            var total = 0.0, mix = 0.0, strong = 0
            for position in [0.15, 0.50, 0.85] {
                if cancelled() { return false }
                file.framePosition = Int64(Double(file.length - Int64(capacity)) * position)
                try file.read(into: buffer, frameCount: capacity)
                let end = Int(buffer.frameLength)
                guard end > warmup, let channels = buffer.floatChannelData else { continue }
                var leftSum = 0.0, rightSum = 0.0, power = 0.0, sumPower = 0.0
                for frame in warmup..<end {
                    let left = Double(channels[0][frame]), right = Double(channels[1][frame])
                    leftSum += left
                    rightSum += right
                    power += left * left + right * right
                    sumPower += (left + right) * (left + right)
                }
                let count = Double(end - warmup)
                let stereo = (power - (leftSum * leftSum + rightSum * rightSum) / count) / 2
                let sum = leftSum + rightSum
                let mono = (sumPower - sum * sum / count) / 4
                if stereo < count * 0.0001 { continue } // -40 dBFS RMS
                if mono >= stereo * 0.5 { return false }
                if mono <= stereo * 0.0631 { strong += 1 } // at least 12 dB lost
                total += stereo
                mix += mono
            }
            return strong >= 2 && mix <= total * 0.0631
        } catch {
            return false
        }
    }

    static func restore(_ buffer: AVAudioPCMBuffer) {
        let right = buffer.floatChannelData![1]
        for frame in 0..<Int(buffer.frameLength) { right[frame] = -right[frame] }
    }
}
