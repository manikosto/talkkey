import AppKit
import ApplicationServices

/// The "type in your language, send in theirs" action.
///
/// Reads what is in the focused text field — the selection if there is one,
/// otherwise the whole field — translates it, and types the translation back
/// over it. Nothing is sent anywhere by TalkKey: the user still presses Enter
/// themselves, after seeing the result.
@MainActor
final class TextFieldTranslator {
    static let shared = TextFieldTranslator()

    private var isRunning = false

    private init() {}

    enum Outcome {
        /// The field now holds this translation.
        case replaced(String)
        case alreadyInTarget
        case nothingToTranslate
        case failed
        /// Another run is still in progress.
        case busy
    }

    /// Runs the whole action and reports through the result toast.
    func translateFocusedText(to target: TranslationLanguage) {
        Task { @MainActor in
            _ = await translateFocusedText(to: target, quietSuccess: false)
        }
    }

    /// Same, but tells the caller what happened. `quietSuccess` skips the
    /// success toast for flows where the result is obvious (Enter mode).
    func translateFocusedText(to target: TranslationLanguage, quietSuccess: Bool) async -> Outcome {
        guard !isRunning else { return .busy }
        isRunning = true
        defer { isRunning = false }
        return await run(target: target, quietSuccess: quietSuccess)
    }

    private func run(target: TranslationLanguage, quietSuccess: Bool) async -> Outcome {
        print("TextFieldTranslator: target=\(target.rawValue) trusted=\(AXIsProcessTrusted())")
        guard AXIsProcessTrusted() else {
            ResultToastController.shared.show(
                kind: .warning,
                title: "Accessibility access needed",
                detail: "TalkKey reads and replaces the text in the field through Accessibility. Grant it in Settings, then try again.",
                duration: 10
            )
            return .failed
        }

        // Remember where the text lives so typing goes back to the same app,
        // even if a menu or toast briefly takes focus.
        PasteboardManager.shared.saveCurrentApp()

        let capture = PasteboardManager.shared.captureFocusedText()
        print("TextFieldTranslator: captured \(capture?.text.count ?? -1) chars, selection=\(capture?.isSelection ?? false)")
        guard let capture else {
            ResultToastController.shared.show(
                kind: .info,
                title: "Nothing to translate",
                detail: "Click into a text field with some text, then tap the key again.",
                duration: 6
            )
            return .nothingToTranslate
        }

        let source = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            ResultToastController.shared.show(
                kind: .info,
                title: "The field is empty",
                detail: "Type something first, then tap the key to translate it.",
                duration: 6
            )
            return .nothingToTranslate
        }

        if let detected = TranslationService.shared.detectLanguage(of: source), detected == target {
            ResultToastController.shared.show(
                kind: .info,
                title: "Already in \(target.fullName)",
                detail: "The text is left as it is.",
                duration: 4
            )
            return .alreadyInTarget
        }

        AppState.shared.isTranslatingText = true
        defer { AppState.shared.isTranslatingText = false }

        do {
            let result = try await TranslationService.shared.translateDetailed(text: source, to: target)
            let translated = result.text
            print("TextFieldTranslator: translated \(result.engine.label): \(translated.prefix(80))")
            guard !translated.isEmpty else { throw TranslationError.invalidResponse }

            PasteboardManager.shared.replaceFocusedText(
                with: translated,
                selectionOnly: capture.isSelection
            )
            HistoryManager.shared.add(translated)

            if !quietSuccess {
                ResultToastController.shared.show(
                    kind: .success,
                    title: "Translated to \(target.fullName) \(result.engine.label)",
                    detail: translated,
                    copyText: translated,
                    duration: 5
                )
            }
            return .replaced(translated)
        } catch {
            print("TextFieldTranslator: failed: \(error)")
            ResultToastController.shared.show(
                kind: .error,
                title: "Translation failed",
                detail: error.localizedDescription,
                copyText: source,
                duration: 10
            )
            return .failed
        }
    }
}
