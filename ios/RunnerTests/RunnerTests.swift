import AVFoundation
import XCTest
@testable import quran_pcm_audio

final class RunnerTests: XCTestCase {
    func testThreeRecordingsContinueWhileMainThreadIsBlocked() throws {
        XCTAssertTrue(Thread.isMainThread)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        defer { try? FileManager.default.removeItem(at: path) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let frames: AVAudioFrameCount = 52920 // 1.2 s: exceeds the one-second producer window.
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<2 {
            for frame in 0..<Int(frames) { buffer.floatChannelData![channel][frame] = 0.001 }
        }
        do { let file = try AVAudioFile(forWriting: path, settings: format.settings); try file.write(from: buffer) }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        defer { try? session.setActive(false) }
        let output = try PcmOutput(generation: 10, seconds: 1, seek: 0)
        defer { output.cancel() }
        for index in 0..<3 { try output.enqueue(["id": "surah-\(index)", "path": path.path]) }
        output.start(); output.finish(); try output.setPlaying(true)
        let deadline = Date().addingTimeInterval(10)
        var paused = false
        while Date() < deadline {
            // Deliberately do not pump main, including completions or UI timers.
            Thread.sleep(forTimeInterval: 0.05)
            let snapshot = output.snapshot()
            XCTAssertNil(snapshot["error"])
            let played = snapshot["frames"] as! Int64
            XCTAssertLessThanOrEqual(snapshot["pcmBufferedFrames"] as! Int64, 44100)
            if !paused && played > 4410 {
                try output.setPlaying(false)
                let position = output.snapshot()["frames"] as! Int64
                Thread.sleep(forTimeInterval: 0.15)
                XCTAssertEqual(output.snapshot()["frames"] as! Int64, position)
                try output.setPlaying(true)
                paused = true
            }
            if snapshot["state"] as? String == "completed" {
                XCTAssertEqual(played, Int64(frames) * 3)
                XCTAssertTrue(paused)
                let rows = snapshot["rows"] as! [[String: Any]]
                XCTAssertEqual(rows.count, 3)
                for (index, row) in rows.enumerated() {
                    XCTAssertEqual(row["start"] as? Int64, Int64(index) * Int64(frames))
                    XCTAssertEqual(row["end"] as? Int64, Int64(index + 1) * Int64(frames))
                }
                XCTAssertGreaterThan(snapshot["scheduledBuffers"] as! Int, 30)
                return
            }
        }
        XCTFail("PCM output stalled while the main thread was blocked")
    }

    func testIncrementalDecodePreservesStereoFramesIncludingSilence() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        defer { try? FileManager.default.removeItem(at: path) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let frames: AVAudioFrameCount = 12017
        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        input.frameLength = frames
        for channel in 0..<2 {
            for frame in 0..<Int(frames) {
                input.floatChannelData![channel][frame] = frame < 300 || frame > 11800 ? 0 : Float((frame + channel) % 199) / 256
            }
        }
        do {
            let file = try AVAudioFile(forWriting: path, settings: format.settings)
            try file.write(from: input)
        }
        var position = 0
        var chunks = 0
        try PcmDecoder.decode(path: path.path, cancelled: { false }) { output in
            XCTAssertLessThanOrEqual(output.frameLength, 4096)
            for channel in 0..<2 {
                for frame in 0..<Int(output.frameLength) {
                    XCTAssertEqual(output.floatChannelData![channel][frame], input.floatChannelData![channel][position + frame])
                }
            }
            position += Int(output.frameLength)
            chunks += 1
        }
        XCTAssertEqual(position, Int(frames))
        XCTAssertGreaterThan(chunks, 1)
    }
    func testMissingRecordingFailsRatherThanSkippingRecitation() throws {
        XCTAssertThrowsError(try PcmDecoder.decode(path: "/missing/recording.mp3", cancelled: { false }, emit: { _ in XCTFail() }))
    }

    func testContinuousOutputKeepsExactOccurrenceBoundaries() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        defer { try? FileManager.default.removeItem(at: path) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
        buffer.frameLength = 4410
        for channel in 0..<2 {
            for frame in 0..<4410 { buffer.floatChannelData![channel][frame] = 0.001 }
        }
        do {
            let file = try AVAudioFile(forWriting: path, settings: format.settings)
            try file.write(from: buffer)
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        defer { try? session.setActive(false) }
        let output = try PcmOutput(generation: 1, seconds: 1, seek: 0)
        defer { output.cancel() }
        for index in 0..<3 { try output.enqueue(["id": "occurrence-\(index)", "path": path.path]) }
        output.start()
        output.finish()
        try output.setPlaying(true)
        let done = expectation(description: "All samples presented")
        var timer: Timer?
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            let snapshot = output.snapshot()
            if let error = snapshot["error"] {
                XCTFail(String(describing: error)); timer?.invalidate(); done.fulfill(); return
            }
            if snapshot["state"] as? String == "completed" {
                XCTAssertEqual(snapshot["frames"] as? Int64, 13230)
                let rows = snapshot["rows"] as! [[String: Any]]
                XCTAssertEqual(rows.count, 3)
                for (index, row) in rows.enumerated() {
                    XCTAssertEqual(row["start"] as? Int64, Int64(index * 4410))
                    XCTAssertEqual(row["end"] as? Int64, Int64((index + 1) * 4410))
                }
                timer?.invalidate(); done.fulfill()
            }
        }
        defer { timer?.invalidate() }
        wait(for: [done], timeout: 10)
    }
}
