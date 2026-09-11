import AppKit
import CoreGraphics

/// "Type in your language, press Enter, it goes out in theirs."
///
/// Per app: while the mode is on for, say, Telegram, a plain Enter there is
/// swallowed, the field is translated in place, and Enter is sent again by
/// TalkKey. Shift/⌘/⌥/⌃+Enter pass through untouched, so newline shortcuts
/// keep working. A failed translation sends nothing — the text stays as typed.
///
/// Toggled by holding a Translate-text key, or from the menu bar. Kept per
/// bundle identifier and persisted, so a chat app stays in "send translated"
/// mode across launches; the control bar and menu bar show when it is on.
@MainActor
final class EnterTranslationMode {
    static let shared = EnterTranslationMode()

    /// Stamped on the Enter events TalkKey posts itself, so its own tap lets
    /// them through instead of translating a second time.
    nonisolated static let ownEventMarker: Int64 = 0x54_4B_45_59 // "TKEY"

    private let storageKey = "enterTranslationPerApp"

    /// bundle id → target language code.
    private var targets: [String: String] {
        didSet { UserDefaults.standard.set(targets, forKey: storageKey) }
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHandlingEnter = false

    private init() {
        targets = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshFrontmostState() }
        }
        refreshFrontmostState()
        if !targets.isEmpty { installTap() }
    }

    // MARK: - State

    func target(for bundleId: String) -> TranslationLanguage? {
        targets[bundleId].flatMap { TranslationLanguage(rawValue: $0) }
    }

    /// The app the user is working in — never TalkKey itself.
    var frontmostBundleId: String? {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              id != Bundle.main.bundleIdentifier else { return nil }
        return id
    }

    var frontmostAppName: String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "this app"
    }

    /// Turns the mode on (or off, if already on) for the frontmost app.
    func toggleForFrontmostApp(target: TranslationLanguage) {
        guard let bundleId = frontmostBundleId else {
            ResultToastController.shared.show(
                kind: .info,
                title: "Switch to the app first",
                detail: "Translate on Enter is set per app. Click into the app you want it in, then hold the key again.",
                duration: 6
            )
            return
        }
        let appName = frontmostAppName

        if targets[bundleId] != nil {
            targets.removeValue(forKey: bundleId)
            ResultToastController.shared.show(
                kind: .info,
                title: "Translate on Enter: off in \(appName)",
                detail: "Enter sends messages as typed again.",
                duration: 4
            )
        } else {
            targets[bundleId] = target.rawValue
            ResultToastController.shared.show(
                kind: .success,
                title: "Translate on Enter: on in \(appName) → \(target.displayName)",
                detail: "Type in your own language and press Enter; the message goes out translated. Shift+Enter sends as typed. Hold the key again to turn off.",
                duration: 8
            )
        }

        if targets.isEmpty { removeTap() } else { installTap() }
        refreshFrontmostState()
    }

    private func refreshFrontmostState() {
        AppState.shared.enterTranslation = frontmostBundleId.flatMap { target(for: $0) }
    }

    // MARK: - Event tap

    private func installTap() {
        guard tap == nil else { return }
        guard AXIsProcessTrusted() else {
            ResultToastController.shared.show(
                kind: .warning,
                title: "Accessibility access needed",
                detail: "Translate on Enter watches for the Enter key, which needs Accessibility access. Grant it in Settings.",
                duration: 10
            )
            return
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let mode = Unmanaged<EnterTranslationMode>.fromOpaque(refcon).takeUnretainedValue()
                // The tap's run-loop source lives on the main run loop.
                return MainActor.assumeIsolated { mode.handle(type: type, event: event) }
            },
            userInfo: refcon
        ) else {
            print("EnterTranslationMode: could not create event tap")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS switches a tap off if its callback ever stalls; switch it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 36 || keyCode == 76 else { return Unmanaged.passUnretained(event) }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.ownEventMarker else {
            return Unmanaged.passUnretained(event)
        }
        // Modified Enter is the app's own business (newline, send-with-cmd…).
        let modifiers: CGEventFlags = [.maskShift, .maskCommand, .maskAlternate, .maskControl]
        guard event.flags.intersection(modifiers).isEmpty else { return Unmanaged.passUnretained(event) }

        guard let bundleId = frontmostBundleId,
              let target = target(for: bundleId) else {
            return Unmanaged.passUnretained(event)
        }
        // An impatient second Enter while the first is still translating must
        // not slip the untranslated text out; swallow it.
        guard !isHandlingEnter else { return nil }

        isHandlingEnter = true
        Task { @MainActor in
            await self.translateThenSend(target: target)
            self.isHandlingEnter = false
        }
        return nil
    }

    private func translateThenSend(target: TranslationLanguage) async {
        let outcome = await TextFieldTranslator.shared.translateFocusedText(to: target, quietSuccess: true)
        switch outcome {
        case .replaced(let text):
            // Let the app finish consuming the typed characters before Enter.
            let settle = min(1.2, 0.2 + Double(text.count) / 1500)
            try? await Task.sleep(for: .seconds(settle))
            PasteboardManager.shared.postReturn()
        case .alreadyInTarget, .nothingToTranslate:
            PasteboardManager.shared.postReturn()
        case .failed, .busy:
            break // Nothing sent; the typed text is still there.
        }
    }
}
