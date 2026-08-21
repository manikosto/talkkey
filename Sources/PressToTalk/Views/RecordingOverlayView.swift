import SwiftUI
import AppKit

/// The floating recording pill.
///
/// Everything animated here is driven by a single TimelineView — the pulse,
/// the waveform scroll, and the timer all derive from the frame timestamp.
/// There are no Combine subscriptions and no `.repeatForever` animations, so
/// nothing can keep running after the window is released.
struct RecordingOverlayView: View {
    let mode: CurrentRecordingMode
    let startedAt: Date

    private var accent: Color {
        switch mode {
        case .directPaste: return Color(red: 1.0, green: 0.35, blue: 0.25)
        case .review: return Color(red: 0.75, green: 0.5, blue: 1.0)
        case .translation: return Color(red: 0.35, green: 0.65, blue: 1.0)
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            HStack(spacing: 12) {
                pulsingDot(time: t)

                WaveformCanvas(accent: accent, frameTime: t)
                    .frame(width: 132, height: 26)

                Text(elapsedString(now: timeline.date))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65))
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(accent.opacity(0.06))
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.08),
                                    accent.opacity(0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: accent.opacity(0.25), radius: 18, y: 6)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        }
        .frame(width: 280, height: 72)
    }

    private func pulsingDot(time: TimeInterval) -> some View {
        // Smooth breathing pulse: period 1.6s
        let pulse = 0.5 + 0.5 * sin(time * (2 * .pi / 1.6))
        return ZStack {
            Circle()
                .fill(accent.opacity(0.35 * pulse))
                .frame(width: 20, height: 20)
                .blur(radius: 4)
            Circle()
                .fill(accent)
                .frame(width: 10, height: 10)
                .scaleEffect(0.9 + 0.25 * pulse)
                .shadow(color: accent.opacity(0.8), radius: 3 + 5 * pulse)
        }
        .frame(width: 22, height: 22)
    }

    private func elapsedString(now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(startedAt)))
        return String(format: "%d:%02d", elapsed / 60, elapsed % 60)
    }
}

/// Scrolling waveform drawn as a single Canvas.
///
/// Bars are historical levels from AudioLevelStore; the fractional scroll phase
/// between pushes makes the movement continuous instead of stepping ~25x/sec.
private struct WaveformCanvas: View {
    let accent: Color
    /// Changes every frame so SwiftUI's diffing never skips the Canvas redraw.
    let frameTime: TimeInterval

    var body: some View {
        Canvas { context, size in
            _ = frameTime
            let (levels, phase) = AudioLevelStore.shared.snapshot()
            let count = levels.count
            guard count > 0 else { return }

            let step = size.width / CGFloat(count - 1)
            let barWidth: CGFloat = max(2, step * 0.55)
            let midY = size.height / 2
            let minHalf: CGFloat = 1.2
            let maxHalf = size.height / 2

            for i in 0..<count {
                // Slide everything left by the scroll phase; the newest bar
                // eases in from the right, the oldest fades out on the left.
                let x = CGFloat(i) * step - phase * step
                guard x > -step, x < size.width + step else { continue }

                var level = CGFloat(levels[i])
                var alpha: CGFloat = 1

                if i == count - 1 {
                    level *= phase                       // grow in
                } else if i == 0 {
                    alpha = 1 - phase                    // fade out
                }
                // Edge fade for a soft mask on both sides
                let edge = min(x / (step * 3), (size.width - x) / (step * 3))
                alpha *= min(1, max(0, edge))

                let half = max(minHalf, level * maxHalf)
                let rect = CGRect(
                    x: x - barWidth / 2,
                    y: midY - half,
                    width: barWidth,
                    height: half * 2
                )
                let intensity = 0.45 + 0.55 * level
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(accent.opacity(alpha * intensity))
                )
            }
        }
    }
}

// MARK: - Window controller

/// Owns the overlay panel. The panel is created on show and fully released
/// after the fade-out completes, so nothing animates while hidden.
@MainActor
final class RecordingOverlayWindowController {
    static let shared = RecordingOverlayWindowController()

    private var panel: NSPanel?
    private var generation = 0

    func show() {
        generation &+= 1

        // A hide fade may be in flight — discard that panel and start clean.
        if let old = panel {
            old.orderOut(nil)
            old.contentView = nil
            panel = nil
        }

        let view = RecordingOverlayView(
            mode: AppState.shared.currentRecordingMode,
            startedAt: Date()
        )
        let hostingView = NSHostingView(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false          // SwiftUI draws its own soft shadows
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        // Final position: bottom center; start slightly lower for a rise-in.
        let finalOrigin = targetOrigin(for: panel)
        panel.setFrameOrigin(NSPoint(x: finalOrigin.x, y: finalOrigin.y - 12))
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(finalOrigin)
        }

        self.panel = panel
    }

    func hide() {
        generation &+= 1
        let gen = generation
        guard let panel = panel else { return }

        let downOrigin = NSPoint(x: panel.frame.origin.x, y: panel.frame.origin.y - 10)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(downOrigin)
        }, completionHandler: {
            Task { @MainActor in
                // Only release if no new show() started during the fade.
                guard self.generation == gen, let panel = self.panel else { return }
                panel.orderOut(nil)
                panel.contentView = nil
                self.panel = nil
            }
        })
    }

    private func targetOrigin(for window: NSWindow) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let screenFrame = screen.visibleFrame
        return NSPoint(
            x: screenFrame.midX - window.frame.width / 2,
            y: screenFrame.minY + 80
        )
    }
}
