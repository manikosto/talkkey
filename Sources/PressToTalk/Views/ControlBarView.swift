import SwiftUI
import AppKit

/// Always-available floating controls: start/stop dictation by clicking
/// instead of holding a key, switch mode, jump to history.
///
/// Clicking must never steal focus — the whole paste flow depends on the
/// target app staying frontmost — so the panel is non-activating and each
/// button acts without making the app key.
struct ControlBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings = SettingsManager.shared
    @State private var expanded = false

    private var accent: Color {
        switch appState.currentRecordingMode {
        case .directPaste: return Color(red: 1.0, green: 0.35, blue: 0.25)
        case .review: return Color(red: 0.75, green: 0.5, blue: 1.0)
        case .translation: return Color(red: 0.35, green: 0.65, blue: 1.0)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            if expanded {
                modeChips
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 8) {
                recordButton

                if appState.isRecording {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                        MiniWaveform(accent: accent, frameTime: timeline.date.timeIntervalSinceReferenceDate)
                            .frame(width: 78, height: 22)
                    }
                    .transition(.opacity)
                } else if appState.isTranscribing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                        Text("Transcribing")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .transition(.opacity)
                }

                circleButton(icon: "clock.fill", tip: "History") {
                    MainWindowController.shared.show()
                    NotificationCenter.default.post(name: .init("switchToHistory"), object: nil)
                }

                circleButton(icon: expanded ? "chevron.down" : "chevron.up", tip: "More") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        expanded.toggle()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Color.black.opacity(0.3))
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.28), Color.white.opacity(0.07)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(0.4), radius: 14, y: 5)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: appState.isRecording)
        .animation(.easeInOut(duration: 0.2), value: appState.isTranscribing)
        .padding(26)
    }

    private var recordButton: some View {
        Button(action: { HotkeyManager.shared.toggleRecordingFromUI() }) {
            ZStack {
                Circle()
                    .fill(appState.isRecording ? accent : Color.white.opacity(0.12))
                    .frame(width: 34, height: 34)

                if appState.isRecording {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                } else {
                    Circle()
                        .fill(accent)
                        .frame(width: 14, height: 14)
                }
            }
            .shadow(color: appState.isRecording ? accent.opacity(0.6) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
        .help(appState.isRecording ? "Stop and transcribe" : "Start dictation")
    }

    private var modeChips: some View {
        HStack(spacing: 6) {
            modeChip(.directPaste, icon: "bolt.fill", label: "Paste")
            modeChip(.review, icon: "wand.and.stars", label: "Review")
            modeChip(.translation, icon: "globe", label: "Translate")
        }
        .padding(6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
    }

    private func modeChip(_ mode: CurrentRecordingMode, icon: String, label: String) -> some View {
        let isSelected = appState.currentRecordingMode == mode
        return Button(action: {
            guard !appState.isRecording else { return }
            appState.currentRecordingMode = mode
        }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isSelected ? Color.white.opacity(0.16) : Color.clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(appState.isRecording)
    }

    private func circleButton(icon: String, tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help(tip)
    }
}

/// Compact waveform for the control bar, same store as the big overlay.
private struct MiniWaveform: View {
    let accent: Color
    let frameTime: TimeInterval

    var body: some View {
        Canvas { context, size in
            _ = frameTime
            let (levels, phase) = AudioLevelStore.shared.snapshot()
            guard levels.count > 1 else { return }

            let step = size.width / CGFloat(levels.count - 1)
            let barWidth: CGFloat = max(1.5, step * 0.5)
            let midY = size.height / 2

            for i in levels.indices {
                let x = CGFloat(i) * step - phase * step
                guard x > -step, x < size.width + step else { continue }

                var level = CGFloat(levels[i])
                var alpha: CGFloat = 1
                if i == levels.count - 1 { level *= phase }
                else if i == 0 { alpha = 1 - phase }

                let half = max(1, level * size.height / 2)
                let rect = CGRect(x: x - barWidth / 2, y: midY - half, width: barWidth, height: half * 2)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(accent.opacity(alpha * (0.5 + 0.5 * level)))
                )
            }
        }
    }
}

// MARK: - Window controller

@MainActor
final class ControlBarController {
    static let shared = ControlBarController()

    private let visibilityKey = "controlBarVisible"
    private var panel: NSPanel?

    var isVisible: Bool { panel != nil }

    /// Restores the bar on launch if the user had it open.
    func restoreIfNeeded() {
        if UserDefaults.standard.bool(forKey: visibilityKey) {
            show()
        }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        UserDefaults.standard.set(true, forKey: visibilityKey)
        guard panel == nil else { return }

        let hostingView = NSHostingView(rootView: ControlBarView(appState: AppState.shared))
        let size = NSSize(width: 340, height: 130)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        // Clickable without pulling focus away from whatever the user is typing in
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.setFrameAutosaveName("TalkKeyControlBar")

        if panel.frame.origin == .zero, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 24, y: visible.minY + 24))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }

        self.panel = panel
    }

    func hide() {
        UserDefaults.standard.set(false, forKey: visibilityKey)
        guard let panel = panel else { return }
        self.panel = nil

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.contentView = nil
        })
    }
}
