import Foundation

struct PcmScheduledSpan {
    let streamStart: Int64
    let nodeStart: Int64
    let frames: Int64
}

/// Sample time excludes genuine wall-clock underruns. Never infer played frames
/// from queued buffers or elapsed UI time. Caller serializes access.
struct PcmFrameClock {
    private(set) var played: Int64 = 0
    private(set) var scheduled: Int64 = 0
    private(set) var renderedAny = false
    private var nodeEnd: Int64 = 0
    private var spans: [PcmScheduledSpan] = []

    mutating func skip(to frame: Int64, frames: Int64) {
        played = max(played, frame)
        scheduled += frames
    }
    mutating func append(start: Int64, frames: Int64, nodeTime: Int64, safety: Int64) -> PcmScheduledSpan {
        let next = max(nodeEnd, nodeTime + (spans.isEmpty ? safety : 0))
        let span = PcmScheduledSpan(streamStart: start, nodeStart: next, frames: frames)
        spans.append(span)
        nodeEnd = next + frames
        scheduled += frames
        return span
    }
    mutating func advance(renderedNodeFrame: Int64) {
        for span in spans where renderedNodeFrame >= span.nodeStart {
            played = max(played, span.streamStart + min(span.frames, renderedNodeFrame - span.nodeStart))
            if renderedNodeFrame > span.nodeStart { renderedAny = true }
        }
    }
    mutating func complete(_ span: PcmScheduledSpan, playing: Bool) {
        guard playing else { return }
        played = max(played, span.streamStart + span.frames)
        renderedAny = true
        spans.removeAll { $0.streamStart <= span.streamStart }
    }
}
