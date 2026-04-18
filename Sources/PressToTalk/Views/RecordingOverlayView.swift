import SwiftUI
import AppKit

struct RecordingOverlayView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                // Pulsing coral/red-orange circle
                Circle()
                    .fill(Color(red: 1.0, green: 0.35, blue: 0.25))
                    .frame(width: 10, height: 10)
                    .shadow(color: Color(red: 1.0, green: 0.35, blue: 0.25).opacity(0.6), radius: appState.isRecording ? 6 : 2)
                    .scaleEffect(appState.isRecording ? 1.3 : 1.0)
                    .opacity(appState.isRecording ? 0.75 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: appState.isRecording)

                // Waveform
                WaveformView(levels: appState.audioLevels)
                    .frame(width: 100, height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    // Glass background
                    Capsule()
                        .fill(.ultraThinMaterial)
                    // Subtle border for glass edge
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                }
            )
        }
        .frame(width: 180, height: 60)
    }
}

struct WaveformView: View {
    let levels: [CGFloat]
    private let barCount = 24

    private var visibleLevels: [CGFloat] {
        Array(levels.suffix(barCount))
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<visibleLevels.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 2, height: max(2, visibleLevels[index] * 20))
            }
        }
    }
}

// Window controller for the overlay
class RecordingOverlayWindowController {
    static let shared = RecordingOverlayWindowController()

    private var window: NSWindow?

    @MainActor
    func show() {
        if let window = window {
            // Reposition in case screen changed
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let windowFrame = window.frame
                let x = screenFrame.midX - windowFrame.width / 2
                let y = screenFrame.minY + 80
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
            window.orderFront(nil)
            return
        }

        let contentView = RecordingOverlayView(appState: AppState.shared)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 60),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Position at bottom center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.minY + 80
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.orderFront(nil)
        self.window = window
    }

    @MainActor
    func hide() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }
}
