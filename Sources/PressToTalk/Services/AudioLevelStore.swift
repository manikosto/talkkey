import Foundation
import QuartzCore

/// Lock-protected audio level history written from the audio thread and read
/// by the overlay's render loop each frame.
///
/// Deliberately NOT an ObservableObject: level updates arrive ~25x/sec and must
/// never trigger SwiftUI invalidation outside the overlay waveform. The waveform
/// pulls a snapshot per frame via TimelineView instead of being pushed updates.
final class AudioLevelStore: @unchecked Sendable {
    static let shared = AudioLevelStore()

    /// Number of history samples kept (== bars drawn by the waveform).
    /// Denser than the visible bar spacing needs, which is what gives the
    /// waveform its fine-grained look rather than a row of chunky blocks.
    static let capacity = 42

    /// Target interval between pushes; the renderer uses this to interpolate
    /// a continuous scroll between discrete samples.
    static let pushInterval: CFTimeInterval = 0.04

    private let lock = NSLock()
    private var levels: [Float]
    private var writeIndex = 0
    private var lastPushTime: CFTimeInterval = 0

    private init() {
        levels = Array(repeating: 0, count: Self.capacity)
    }

    func push(_ level: Float) {
        lock.lock()
        levels[writeIndex % Self.capacity] = level
        writeIndex += 1
        lastPushTime = CACurrentMediaTime()
        lock.unlock()
    }

    /// Levels ordered oldest → newest, plus the scroll phase [0, 1] — how far
    /// we are between the last push and the expected next one.
    func snapshot() -> (levels: [Float], phase: CGFloat) {
        lock.lock()
        defer { lock.unlock() }
        let n = Self.capacity
        let start = writeIndex % n
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            out[i] = levels[(start + i) % n]
        }
        let elapsed = CACurrentMediaTime() - lastPushTime
        let phase = CGFloat(min(1.0, max(0.0, elapsed / Self.pushInterval)))
        return (out, phase)
    }

    func reset() {
        lock.lock()
        levels = Array(repeating: 0, count: Self.capacity)
        writeIndex = 0
        lastPushTime = 0
        lock.unlock()
    }
}
