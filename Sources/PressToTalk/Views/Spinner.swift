import SwiftUI

/// Smooth gradient-arc spinner.
///
/// Replaces `ProgressView()`, whose AppKit indicator draws as a ring of hard
/// spokes that looks dated and, on a light background, muddy.
///
/// Driven by the frame clock instead of a `.repeatForever` animation, so it
/// cannot keep spinning after its view goes away.
struct Spinner: View {
    var size: CGFloat = 16
    var color: Color = Theme.accentBlue
    var lineWidth: CGFloat = 2
    /// Seconds per revolution.
    var period: Double = 0.9

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let turn = (t.truncatingRemainder(dividingBy: period)) / period

            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: 0.68)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                color.opacity(0),
                                color.opacity(0.55),
                                color
                            ]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(turn * 360))
            }
            .frame(width: size, height: size)
        }
    }
}

/// Determinate ring for downloads, so a long model fetch shows real progress
/// instead of an endless spin.
struct ProgressRing: View {
    var progress: Double
    var size: CGFloat = 16
    var color: Color = Theme.accentOrange
    var lineWidth: CGFloat = 2

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: progress)
        }
        .frame(width: size, height: size)
    }
}

/// Three-dot pulse for inline "working" states where a ring would be too heavy.
struct DotsLoader: View {
    var color: Color = Theme.textTertiary
    var dot: CGFloat = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: dot * 0.8) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t * 2.2) - Double(i) * 0.35
                    let wave = (sin(phase) + 1) / 2
                    Circle()
                        .fill(color.opacity(0.35 + 0.65 * wave))
                        .frame(width: dot, height: dot)
                        .scaleEffect(0.75 + 0.35 * wave)
                }
            }
        }
    }
}
