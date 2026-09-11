import AppKit
import CoreGraphics

class PasteboardManager {
    static let shared = PasteboardManager()

    // Store the app that was active when recording started
    private var targetAppBundleId: String?

    func saveCurrentApp() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }

        // Interacting with the control bar (a quick-settings menu, say) can
        // make TalkKey frontmost. Targeting ourselves would type the
        // transcript into our own window instead of the user's document, so
        // keep the previous target in that case.
        guard frontmost != Bundle.main.bundleIdentifier else { return }

        targetAppBundleId = frontmost
    }

    /// What happened to a transcript.
    enum PasteOutcome {
        /// Typed into the focused field; the clipboard was left alone.
        case typed
        /// Nowhere to type it, so it was put on the clipboard instead.
        case copiedNoTextField
        /// Accessibility isn't granted, so typing is impossible.
        case copiedNoAccessibility
    }

    /// Types the transcript into whatever the user was working in.
    ///
    /// The clipboard is deliberately *not* touched on the normal path: people
    /// keep things there, and clobbering it on every dictation is its own kind
    /// of data loss. It is used only as a fallback when there is nowhere to
    /// type — and nothing is ever lost regardless, because every transcript is
    /// kept in History and offered by the result card.
    @discardableResult
    func pasteText(_ text: String) -> PasteOutcome {
        // Without Accessibility trust CGEvent posting goes nowhere.
        guard AXIsProcessTrusted() else {
            copyToClipboard(text)
            return .copiedNoAccessibility
        }

        // Activate the target app first, then let focus settle before asking
        // where the caret is.
        if let bundleId = targetAppBundleId,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            app.activate(options: .activateIgnoringOtherApps)
        }

        // Detection decides whether to *also* copy — never whether to type.
        // Accessibility describes text areas inconsistently across apps, so a
        // wrong "no" must not stop the transcript reaching the cursor. Typing
        // into something that turns out not to accept text is harmless; not
        // typing when it would have worked is the failure that matters.
        let looksEditable = focusedElementAcceptsText()

        if !looksEditable || SettingsManager.shared.alwaysCopyToClipboard {
            copyToClipboard(text)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.typeText(text)
        }
        return looksEditable ? .typed : .copiedNoTextField
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Whether the thing with keyboard focus can actually receive typed text.
    ///
    /// Deliberately generous: many apps — Electron, web views, custom editors —
    /// describe their text areas poorly, so anything that looks remotely like a
    /// text context counts. A false "yes" merely types where the user was
    /// already working; a false "no" would send them to the clipboard for no
    /// reason.
    private func focusedElementAcceptsText() -> Bool {
        // Focus follows app activation, which was just requested.
        usleep(120_000)

        guard let element = focusedElement() else { return false }
        return elementAcceptsText(element)
    }

    private func elementAcceptsText(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        if let role = roleRef as? String,
           [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, kAXSearchFieldSubrole].contains(role) {
            return true
        }

        // A settable value is the clearest sign of an editable control.
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return true
        }

        // Web and Electron text areas usually expose a caret or a selection
        // even when their role says nothing useful.
        for attribute in [kAXSelectedTextAttribute, kAXSelectedTextRangeAttribute, kAXInsertionPointLineNumberAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success {
                return true
            }
        }

        return false
    }

    // MARK: - Translate text in place

    /// What was found in the focused field.
    struct FocusedText {
        let text: String
        /// True when the user had a selection, so only that part is replaced.
        let isSelection: Bool
    }

    /// The selection in the focused field, or the field's whole contents.
    ///
    /// Accessibility is asked first. Apps that don't expose their text (some
    /// Electron and web editors) get the keyboard route: select all, copy,
    /// read the clipboard, put the clipboard back. Returns nil when focus
    /// isn't on anything that looks editable — selecting all in, say, Finder
    /// would be a surprise.
    func captureFocusedText() -> FocusedText? {
        guard let element = focusedElement(), elementAcceptsText(element) else { return nil }

        var selectedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
           let selected = selectedRef as? String,
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return FocusedText(text: selected, isSelection: true)
        }

        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let value = valueRef as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return FocusedText(text: value, isSelection: false)
        }

        if let copied = copyAllViaKeyboard(), !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return FocusedText(text: copied, isSelection: false)
        }

        return nil
    }

    /// Types `text` over the focused field: over the selection, or over
    /// everything when `selectionOnly` is false.
    func replaceFocusedText(with text: String, selectionOnly: Bool) {
        activateTargetApp()
        usleep(80_000)
        if !selectionOnly {
            postShortcut(virtualKey: 0, flags: .maskCommand) // ⌘A
            usleep(60_000)
        }
        typeText(text)
    }

    private func activateTargetApp() {
        if let bundleId = targetAppBundleId,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first,
           !app.isActive {
            app.activate(options: .activateIgnoringOtherApps)
        }
    }

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(focusedRef, to: AXUIElement.self)
    }

    /// ⌘A, ⌘C, read the clipboard, then restore whatever was there.
    private func copyAllViaKeyboard() -> String? {
        let pasteboard = NSPasteboard.general
        var saved: [NSPasteboard.PasteboardType: Data] = [:]
        for type in pasteboard.types ?? [] {
            if let data = pasteboard.data(forType: type) { saved[type] = data }
        }
        let changeCount = pasteboard.changeCount

        postShortcut(virtualKey: 0, flags: .maskCommand) // ⌘A
        usleep(60_000)
        postShortcut(virtualKey: 8, flags: .maskCommand) // ⌘C

        // Give the app a moment to service the copy.
        var copied: String?
        for _ in 0..<10 {
            usleep(50_000)
            if pasteboard.changeCount != changeCount {
                copied = pasteboard.string(forType: .string)
                break
            }
        }

        pasteboard.clearContents()
        for (type, data) in saved { pasteboard.setData(data, forType: type) }
        return copied
    }

    private func postShortcut(virtualKey: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    // Paste via clipboard (for Review window - saves and restores clipboard)
    func pasteTextViaClipboard(_ text: String) {
        // Save current clipboard content
        let pasteboard = NSPasteboard.general
        var savedContent: [NSPasteboard.PasteboardType: Data] = [:]
        for type in pasteboard.types ?? [] {
            if let data = pasteboard.data(forType: type) {
                savedContent[type] = data
            }
        }

        // Put our text in clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Activate the target app first
        if let bundleId = targetAppBundleId,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            app.activate(options: .activateIgnoringOtherApps)
        }

        // Wait for app to activate, then paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.simulatePaste()

            // Restore clipboard after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !savedContent.isEmpty {
                    pasteboard.clearContents()
                    for (type, data) in savedContent {
                        pasteboard.setData(data, forType: type)
                    }
                }
            }
        }
    }

    // Type text directly using CGEvent - no clipboard needed!
    private func typeText(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)

        // Convert string to UTF-16 for CGEvent
        let utf16Chars = Array(text.utf16)

        // CGEvent can handle up to 20 characters at a time
        let chunkSize = 20
        var index = 0

        while index < utf16Chars.count {
            let end = min(index + chunkSize, utf16Chars.count)
            let chunk = Array(utf16Chars[index..<end])

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                return
            }

            // Set the unicode string for this chunk
            chunk.withUnsafeBufferPointer { buffer in
                keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: buffer.baseAddress!)
                keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: buffer.baseAddress!)
            }

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)

            // Small delay between chunks
            usleep(5000) // 5ms

            index = end
        }
    }

    // Simulate Cmd+V paste
    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key code for 'V' is 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
