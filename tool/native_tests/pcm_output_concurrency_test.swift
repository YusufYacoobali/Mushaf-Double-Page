import Foundation

@main
struct PcmConcurrencyTests {
    static func main() {
        testSerialOutputDoesNotNeedMain()
        testConsecutiveSamplesAndUnderrunMapping()
        testPausedCompletionsAndSeek()
        print("PCM concurrency/clock tests passed (portable Swift; Apple output capture still required).")
    }
    static func testSerialOutputDoesNotNeedMain() {
        precondition(Thread.isMainThread)
        let audio = PcmAudioQueue()
        let done = DispatchSemaphore(value: 0)
        var events: [Int] = []
        for i in 0..<500 { audio.async { events.append(i) } }
        audio.async { done.signal() }
        // Deliberately block main: no main run loop, timers, or dispatch pumping.
        Thread.sleep(forTimeInterval: 0.15)
        precondition(done.wait(timeout: .now() + 3) == .success)
        audio.sync { precondition(events == Array(0..<500)) }
        precondition(audio.sync { audio.sync { 42 } } == 42)
        let ticked = DispatchSemaphore(value: 0)
        let timer = audio.timer { ticked.signal() }
        Thread.sleep(forTimeInterval: 0.15)
        precondition(ticked.wait(timeout: .now() + 3) == .success)
        timer.cancel()
    }
    static func testConsecutiveSamplesAndUnderrunMapping() {
        var clock = PcmFrameClock()
        let a = clock.append(start: 0, frames: 100, nodeTime: 0, safety: 0)
        let b = clock.append(start: 100, frames: 70, nodeTime: 20, safety: 0)
        precondition(a.nodeStart == 0 && b.nodeStart == 100)
        clock.advance(renderedNodeFrame: 99)
        precondition(clock.played == 99)
        clock.advance(renderedNodeFrame: 100)
        precondition(clock.played == 100)
        clock.advance(renderedNodeFrame: 170)
        precondition(clock.played == 170)
        clock.complete(b, playing: true)
        // A real buffer shortage advances hardware time, never Quran samples.
        let c = clock.append(start: 170, frames: 80, nodeTime: 1000, safety: 10)
        precondition(c.nodeStart == 1010)
        clock.advance(renderedNodeFrame: 1005)
        precondition(clock.played == 170)
        clock.advance(renderedNodeFrame: 1050)
        precondition(clock.played == 210)
        clock.complete(c, playing: true)
        precondition(clock.played == 250 && clock.scheduled == 250)
        // Late earlier completions cannot regress or duplicate played samples.
        clock.complete(a, playing: true)
        precondition(clock.played == 250)
    }
    static func testPausedCompletionsAndSeek() {
        var clock = PcmFrameClock()
        clock.skip(to: 40, frames: 40)
        let span = clock.append(start: 40, frames: 100, nodeTime: 0, safety: 0)
        clock.advance(renderedNodeFrame: 20)
        precondition(clock.played == 60)
        clock.complete(span, playing: false)
        precondition(clock.played == 60)
        clock.advance(renderedNodeFrame: 40)
        precondition(clock.played == 80)
        clock.complete(span, playing: true)
        precondition(clock.played == 140 && clock.scheduled == 140)
    }
}
