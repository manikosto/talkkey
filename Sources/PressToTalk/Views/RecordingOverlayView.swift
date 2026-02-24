import SwiftUI
import AppKit

struct RecordingOverlayView: View {
    @ObservedObject var appState: AppState
    @State private var isPulsing = false

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                // Pulsing blue circle
                Circle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 10)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .opacity(isPulsing ? 0.7 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                    .onAppear { isPulsing = true }

                // Waveform
                WaveformView(levels: appState.audioLevels)
                    .frame(width: 100, height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.85))
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
                    .animation(.linear(duration: 0.08), value: visibleLevels[index])
            }
        }
    }
}

// Window controller for the overlay
class RecordingOverlayWindowController {
    static let shared = RecordingOverlayWindowController()

    private var window: NSWindow?
    private var hostingView: NSHostingView<RecordingOverlayView>?

    @MainActor
    func show() {
        if window != nil {
            window?.orderFront(nil)
            return
        }

        let contentView = RecordingOverlayView(appState: AppState.shared)
        hostingView = NSHostingView(rootView: contentView)
        hostingView?.translatesAutoresizingMaskIntoConstraints = false

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
        window = nil
        hostingView = nil
    }
}
