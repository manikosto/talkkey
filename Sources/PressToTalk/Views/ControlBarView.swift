import SwiftUI
import AppKit

/// The single floating element: compact idle controls that expand into the
/// recording indicator. It replaces the separate recording overlay — one pill
/// on screen instead of two.
///
/// Clicking must never steal focus (the paste flow depends on the target app
/// staying frontmost), so the panel is non-activating throughout.
struct ControlBarView: View {
    @ObservedObject var appState: AppState
    @State private var expanded = false

    private var accent: Color {
        switch appState.currentRecordingMode {
        case .directPaste: return Color(red: 1.0, green: 0.33, blue: 0.24)
        case .review: return Color(red: 0.72, green: 0.47, blue: 1.0)
        case .translation: return Color(red: 0.33, green: 0.62, blue: 1.0)
        }
    }

    private var isActive: Bool { appState.isRecording || appState.isTranscribing }

    var body: some View {
        VStack(spacing: 8) {
            if expanded {
                expandedControls
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }

            pill
        }
        .padding(22)   // room for the glow to fade before the window edge
        .fixedSize()
    }

    // MARK: - Pill

    private var pill: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !appState.isRecording)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            HStack(spacing: appState.isRecording ? 12 : 8) {
                recordButton(time: t)

                if appState.isRecording {
                    WaveformCanvas(accent: accent, frameTime: t)
                        .frame(width: 150, height: 24)

                    Text(elapsed(now: timeline.date))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 38, alignment: .trailing)
                } else if appState.isTranscribing {
                    HStack(spacing: 7) {
                        ProgressView()
                            .scaleEffect(0.45)
                            .frame(width: 12, height: 12)
                        Text("Transcribing")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.trailing, 2)
                }

                chevronButton
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(pillBackground)
            .shadow(color: isActive ? accent.opacity(0.45) : .black.opacity(0.35),
                    radius: isActive ? 20 : 12, y: 4)
            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: appState.isRecording)
        .animation(.easeInOut(duration: 0.22), value: appState.isTranscribing)
    }

    private var pillBackground: some View {
        ZStack {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(Color.black.opacity(0.35))
            // Mode colour washes the pill while active — red for paste,
            // blue for translate, purple for review.
            Capsule().fill(accent.opacity(isActive ? 0.1 : 0))
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: isActive
                            ? [accent.opacity(0.85), accent.opacity(0.35)]
                            : [Color.white.opacity(0.26), Color.white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private func recordButton(time: TimeInterval) -> some View {
        // Breathing pulse, period 1.6s — derived from the frame clock so
        // nothing keeps animating once the panel goes away.
        let pulse = appState.isRecording ? 0.5 + 0.5 * sin(time * (2 * .pi / 1.6)) : 0

        return Button(action: { HotkeyManager.shared.toggleRecordingFromUI() }) {
            ZStack {
                if appState.isRecording {
                    Circle()
                        .fill(accent.opacity(0.4 * pulse))
                        .frame(width: 30, height: 30)
                        .blur(radius: 5)
                }

                Circle()
                    .fill(appState.isRecording ? accent : Color.white.opacity(0.14))
                    .frame(width: 26, height: 26)

                if appState.isRecording {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.white)
                        .frame(width: 9, height: 9)
                } else {
                    Circle()
                        .fill(accent)
                        .frame(width: 11, height: 11)
                        .shadow(color: accent.opacity(0.7), radius: 4)
                }
            }
            .frame(width: 30, height: 30)
            .scaleEffect(appState.isRecording ? 1 + 0.06 * pulse : 1)
        }
        .buttonStyle(.plain)
        .help(appState.isRecording ? "Stop and transcribe" : "Start dictation")
    }

    private var chevronButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { expanded.toggle() }
        }) {
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help("More")
    }

    private func elapsed(now: Date) -> String {
        guard let start = appState.recordingStartedAt else { return "0:00" }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Expanded

    private var expandedControls: some View {
        HStack(spacing: 6) {
            modeChip(.directPaste, icon: "bolt.fill", label: "Paste")
            modeChip(.review, icon: "wand.and.stars", label: "Review")
            modeChip(.translation, icon: "globe", label: "Translate")

            Divider()
                .frame(height: 18)
                .overlay(Color.white.opacity(0.12))

            iconButton("clock.fill", tip: "History") {
                MainWindowController.shared.show()
                NotificationCenter.default.post(name: .init("switchToHistory"), object: nil)
            }
            iconButton("character.book.closed.fill", tip: "Dictionary") {
                MainWindowController.shared.show()
                NotificationCenter.default.post(name: .init("switchToDictionary"), object: nil)
            }
            iconButton("xmark", tip: "Hide control bar") {
                ControlBarController.shared.hide()
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.black.opacity(0.3)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.13), lineWidth: 1))
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
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(isSelected ? Color.white.opacity(0.16) : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(appState.isRecording)
    }

    private func iconButton(_ icon: String, tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(tip)
    }
}

/// Hosting view that reports SwiftUI's ideal size whenever it changes.
///
/// A SwiftUI preference/GeometryReader cannot do this job here: inside a
/// fixed-size borderless panel the reader reports the panel's size, not the
/// content's, so the window never learns it should grow.
final class ControlBarHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: ((CGSize) -> Void)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        if #available(macOS 13.0, *) {
            sizingOptions = [.intrinsicContentSize]
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        reportSize()
    }

    override func layout() {
        super.layout()
        reportSize()
    }

    private func reportSize() {
        var size = intrinsicContentSize
        if size.width <= 1 || size.height <= 1 { size = fittingSize }
        guard size.width > 1, size.height > 1 else { return }
        onSizeChange?(size)
    }
}

/// Scrolling waveform drawn as one Canvas, fed by AudioLevelStore.
///
/// The fractional scroll phase between level pushes makes the movement
/// continuous instead of stepping at the push rate.
struct WaveformCanvas: View {
    let accent: Color
    /// Changes every frame so SwiftUI never skips the redraw.
    let frameTime: TimeInterval

    var body: some View {
        Canvas { context, size in
            _ = frameTime
            let (levels, phase) = AudioLevelStore.shared.snapshot()
            let count = levels.count
            guard count > 1 else { return }

            let step = size.width / CGFloat(count - 1)
            let barWidth: CGFloat = max(1.6, step * 0.5)
            let midY = size.height / 2
            let maxHalf = size.height / 2

            for i in 0..<count {
                let x = CGFloat(i) * step - phase * step
                guard x > -step, x < size.width + step else { continue }

                var level = CGFloat(levels[i])
                var alpha: CGFloat = 1

                if i == count - 1 {
                    level *= phase                      // newest bar grows in
                } else if i == 0 {
                    alpha = 1 - phase                   // oldest fades out
                }
                // Soft mask at both ends
                let edge = min(x / (step * 3), (size.width - x) / (step * 3))
                alpha *= min(1, max(0, edge))

                let half = max(1.1, level * maxHalf)
                let rect = CGRect(x: x - barWidth / 2, y: midY - half,
                                  width: barWidth, height: half * 2)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(accent.opacity(alpha * (0.45 + 0.55 * level)))
                )
            }
        }
    }
}

// MARK: - Window controller

@MainActor
final class ControlBarController: NSObject, NSWindowDelegate {
    static let shared = ControlBarController()

    private let visibilityKey = "controlBarVisibleV2"
    private let originKey = "controlBarOriginV2"

    private var panel: NSPanel?
    /// True when the bar was summoned only to indicate recording and should
    /// disappear again afterwards.
    private var shownForRecordingOnly = false
    /// Guards against persisting a position before the panel has been placed:
    /// the first layout pass fires a resize while the window is still at the
    /// origin, and saving that would pin the bar to the bottom-left corner
    /// on every later launch.
    private var hasPositioned = false

    var isVisible: Bool { panel != nil }

    /// Visible by default — it is the app's recording indicator, not an extra.
    func restoreIfNeeded() {
        let shouldShow = UserDefaults.standard.object(forKey: visibilityKey) as? Bool ?? true
        if shouldShow { show() }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show(persist: Bool = true) {
        if persist { UserDefaults.standard.set(true, forKey: visibilityKey) }
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 90),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false          // SwiftUI paints its own soft glow
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true

        let hostingView = ControlBarHostingView(rootView: ControlBarView(appState: AppState.shared))
        hostingView.onSizeChange = { [weak panel] size in
            guard let panel else { return }
            ControlBarController.shared.resize(panel, to: size)
        }
        panel.contentView = hostingView

        self.panel = panel
        panel.setContentSize(hostingView.fittingSize)
        positionAtDefault(panel)
        hasPositioned = true
        panel.delegate = self

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        UserDefaults.standard.set(false, forKey: visibilityKey)
        dismiss()
    }

    func windowDidMove(_ notification: Notification) {
        guard hasPositioned, let panel = panel else { return }
        saveOrigin(panel)
    }

    private func dismiss() {
        guard let panel = panel else { return }
        saveOrigin(panel)
        hasPositioned = false
        panel.delegate = nil
        self.panel = nil

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.contentView = nil
        })
    }

    // MARK: - Recording presentation

    /// Called when recording starts. If the user hid the bar, summon it for
    /// the duration — otherwise a recording would have no indicator at all.
    func beginRecordingPresentation() {
        if panel == nil {
            shownForRecordingOnly = true
            show(persist: false)
        }
    }

    func endRecordingPresentation() {
        guard shownForRecordingOnly else { return }
        shownForRecordingOnly = false
        dismiss()
    }

    // MARK: - Geometry

    /// Grows and shrinks around a fixed bottom-centre anchor, so expanding
    /// into the recording state does not shove the pill sideways.
    private func resize(_ panel: NSPanel, to size: CGSize) {
        let current = panel.frame
        guard abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5 else { return }

        let frame = NSRect(
            x: current.midX - size.width / 2,
            y: current.minY,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true, animate: false)
    }

    private func positionAtDefault(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame

        if let saved = UserDefaults.standard.string(forKey: originKey) {
            let point = NSPointFromString(saved)
            let candidate = NSRect(origin: point, size: panel.frame.size)
            // Honour a saved spot only if the whole pill is still comfortably
            // on this screen — display arrangements change between launches.
            if visible.insetBy(dx: -8, dy: -8).contains(candidate) {
                panel.setFrameOrigin(point)
                return
            }
        }

        panel.setFrameOrigin(NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.minY + 28
        ))
    }

    private func saveOrigin(_ panel: NSPanel) {
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: originKey)
    }
}
