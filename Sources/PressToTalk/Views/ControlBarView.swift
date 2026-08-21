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
    @ObservedObject var settings = SettingsManager.shared
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
        VStack(spacing: 7) {
            if expanded {
                quickSettings
                    .transition(.opacity.combined(with: .offset(y: 5)))
            }

            pill
        }
        // The glow must fade out completely before the window edge, otherwise
        // it is clipped into a visible rectangle with hard corners.
        .padding(Self.glowMargin)
        .fixedSize()
    }

    /// Comfortably larger than the widest shadow below (radius 14 + y offset).
    private static let glowMargin: CGFloat = 30

    // MARK: - Pill

    private var pill: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !appState.isRecording)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            HStack(spacing: appState.isRecording ? 7 : 5) {
                recordButton(time: t)

                if appState.isRecording {
                    WaveformCanvas(accent: accent, frameTime: t)
                        .frame(width: 84, height: 15)

                    Text(elapsed(now: timeline.date))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 27, alignment: .trailing)
                } else if appState.isTranscribing {
                    HStack(spacing: 5) {
                        ProgressView()
                            .scaleEffect(0.32)
                            .frame(width: 9, height: 9)
                        Text("Transcribing")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.trailing, 1)
                }

                chevronButton
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(pillBackground)
            .shadow(color: isActive ? accent.opacity(0.45) : .black.opacity(0.35),
                    radius: isActive ? 14 : 8, y: 3)
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
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
                        .frame(width: 20, height: 20)
                        .blur(radius: 3.5)
                }

                Circle()
                    .fill(appState.isRecording ? accent : Color.white.opacity(0.14))
                    .frame(width: 18, height: 18)

                if appState.isRecording {
                    RoundedRectangle(cornerRadius: 1.8)
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                } else {
                    Circle()
                        .fill(accent)
                        .frame(width: 7.5, height: 7.5)
                        .shadow(color: accent.opacity(0.7), radius: 3)
                }
            }
            .frame(width: 20, height: 20)
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
                .font(.system(size: 8, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help("Quick settings")
    }

    private func elapsed(now: Date) -> String {
        guard let start = appState.recordingStartedAt else { return "0:00" }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Expanded

    /// Quick settings behind the chevron: the handful of things worth changing
    /// without opening the main window.
    private var quickSettings: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                modeChip(.directPaste, icon: "bolt.fill", label: "Paste")
                modeChip(.review, icon: "wand.and.stars", label: "Review")
                modeChip(.translation, icon: "globe", label: "Translate")
            }

            HStack(spacing: 5) {
                Text("Language")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))

                languageChip(.auto, label: "Auto")
                languageChip(.english, label: "EN")
                languageChip(.russian, label: "RU")

                Menu {
                    ForEach(WhisperLanguage.allCases) { lang in
                        Button(lang.displayName) { settings.selectedLanguage = lang }
                    }
                } label: {
                    Text(isCommonLanguage ? "…" : settings.selectedLanguage.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isCommonLanguage ? .white.opacity(0.5) : .white)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(isCommonLanguage ? 0.06 : 0.16)))

                Spacer(minLength: 2)

                iconButton("character.book.closed.fill", tip: "Dictionary") {
                    MainWindowController.shared.show()
                    NotificationCenter.default.post(name: .init("switchToDictionary"), object: nil)
                }
                iconButton("gearshape.fill", tip: "Settings") {
                    MainWindowController.shared.show()
                    NotificationCenter.default.post(name: .init("switchToSettings"), object: nil)
                }
                // Closes this panel only — the bar itself stays put. Hiding
                // the bar entirely lives in the menu bar item.
                iconButton("xmark", tip: "Close") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        expanded = false
                    }
                }
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 13).fill(Color.black.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.white.opacity(0.13), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
    }

    private var isCommonLanguage: Bool {
        [.auto, .english, .russian].contains(settings.selectedLanguage)
    }

    private func languageChip(_ language: WhisperLanguage, label: String) -> some View {
        let isSelected = settings.selectedLanguage == language
        return Button(action: { settings.selectedLanguage = language }) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(isSelected ? accent.opacity(0.35) : Color.white.opacity(0.06)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func modeChip(_ mode: CurrentRecordingMode, icon: String, label: String) -> some View {
        let isSelected = appState.currentRecordingMode == mode
        return Button(action: {
            guard !appState.isRecording else { return }
            appState.currentRecordingMode = mode
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(isSelected ? Color.white.opacity(0.16) : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(appState.isRecording)
    }

    private func iconButton(_ icon: String, tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 18, height: 18)
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
final class ControlBarController {
    static let shared = ControlBarController()

    private let visibilityKey = "controlBarVisibleV2"

    private var panel: NSPanel?
    /// True when the bar was summoned only to indicate recording and should
    /// disappear again afterwards.
    private var shownForRecordingOnly = false


    var isVisible: Bool { panel != nil }

    /// Visible by default — it is the app's recording indicator, not an extra.
    func restoreIfNeeded() {
        migrateStaleHiddenState()
        let shouldShow = UserDefaults.standard.object(forKey: visibilityKey) as? Bool ?? true
        if shouldShow { show() }
    }

    /// Until 2.19 the close button in the quick settings hid the whole bar and
    /// persisted that, so anyone who dismissed the settings panel lost the bar
    /// for good. Clear that state once so those installs get it back; a
    /// deliberate hide from the menu bar afterwards is still honoured.
    private func migrateStaleHiddenState() {
        let migrationKey = "controlBarHiddenStateResetV3"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        UserDefaults.standard.removeObject(forKey: visibilityKey)
        // Stale autosaved frame from the version that parked the bar in the
        // far-right corner; the bar is centred programmatically now.
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame TalkKeyControlBar")
        UserDefaults.standard.removeObject(forKey: "controlBarVisible")
        UserDefaults.standard.removeObject(forKey: "controlBarOriginV2")
        UserDefaults.standard.set(true, forKey: migrationKey)
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

    private func dismiss() {
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

    /// Grows and shrinks around a fixed bottom-centre anchor, so opening the
    /// quick settings does not shove the pill sideways.
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

    /// Always horizontally centred, sitting just above the Dock.
    ///
    /// The position is deliberately not remembered between launches. A stored
    /// position is a left-corner coordinate, and the bar's width changes every
    /// time the quick settings open — so a remembered spot stops meaning
    /// "centred" the moment the content grows, which is how the bar used to
    /// drift off to one side. Dragging still works within a session.
    private func positionAtDefault(_ panel: NSPanel) {
        guard let screen = activeScreen() else { return }
        let visible = screen.visibleFrame

        // visibleFrame already excludes the Dock, and the window carries the
        // glow margin below the pill.
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.minY
        ))
    }

    /// The display the user is actually working on — the one under the mouse.
    ///
    /// `NSScreen.main` is the screen holding keyboard focus, which for a
    /// menu-bar app at launch can be any attached display, so the bar could
    /// appear on a monitor the user is not even looking at.
    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
