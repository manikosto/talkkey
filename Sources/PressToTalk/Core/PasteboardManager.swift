import AppKit
import CoreGraphics

class PasteboardManager {
    static let shared = PasteboardManager()

    // Store the app that was active when recording started
    private var targetAppBundleId: String?

    func saveCurrentApp() {
        targetAppBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    // Regular paste - type text directly (doesn't use clipboard)
    func pasteText(_ text: String) {
        // Activate the target app first
        if let bundleId = targetAppBundleId,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            app.activate(options: .activateIgnoringOtherApps)
        }

        // Wait for app to activate, then type the text directly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.typeText(text)
        }
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
