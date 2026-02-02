import SwiftUI
import AppKit

struct RecordingOverlayView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 16) {
            // Recording indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(appState.currentRecordingMode.indicatorColor)
                    .frame(width: 8, height: 8)
                Text(appState.currentRecordingMode.displayText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)

                // Show target language for translation mode
                if appState.currentRecordingMode == .translation {
                    Text("→ \(SettingsManager.shared.targetLanguage.flag)")
                        .font(.system(size: 13))
                }
            }

            // Waveform
            WaveformView(levels: appState.audioLevels)
                .frame(width: 180, height: 24)

            Spacer()

            // Hints
            HStack(spacing: 16) {
                HintView(label: "Stop", shortcut: "Release")
                HintView(label: "Cancel", shortcut: "Esc")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
        )
        .frame(width: 520)
    }
}

struct WaveformView: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<levels.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 2, height: max(2, levels[index] * 24))
            }
        }
    }
}

struct HintView: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
            Text(shortcut)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                )
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

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 48),
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
