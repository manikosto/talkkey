import SwiftUI
import Combine

enum CurrentRecordingMode: CaseIterable {
    case directPaste
    case review
    case translation
    /// Not a recording at all: tap the key and whatever is typed in the
    /// focused field is replaced with its translation, before it is sent.
    case translateText

    /// Stable identifier for storing a key's assigned action.
    var storageKey: String {
        switch self {
        case .directPaste: return "directPaste"
        case .review: return "review"
        case .translation: return "translation"
        case .translateText: return "translateText"
        }
    }

    init?(storageKey: String) {
        switch storageKey {
        case "directPaste": self = .directPaste
        case "review": self = .review
        case "translation": self = .translation
        case "translateText": self = .translateText
        default: return nil
        }
    }

    var shortName: String {
        switch self {
        case .directPaste: return "Paste"
        case .review: return "Review"
        case .translation: return "Translate"
        case .translateText: return "Translate text"
        }
    }

    /// Whether the key records audio. Translate text works on what is already
    /// typed, so holding it must not start the microphone.
    var recordsAudio: Bool { self != .translateText }

    /// Review and Translate are Pro; plain dictation is always available.
    var requiresPro: Bool { self != .directPaste }

    var displayText: String {
        switch self {
        case .directPaste: return "Recording"
        case .review: return "Recording (Review)"
        case .translation: return "Translating"
        case .translateText: return "Translating text"
        }
    }

    var indicatorColor: Color {
        switch self {
        case .directPaste: return .red
        case .review: return .orange
        case .translation: return .blue
        case .translateText: return .teal
        }
    }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    // Recording state
    @Published var isRecording = false
    @Published var isTranscribing = false
    /// Typed text is being translated in place (the Translate text action).
    @Published var isTranslatingText = false
    /// Translate on Enter is on for the frontmost app, into this language.
    @Published var enterTranslation: TranslationLanguage?
    @Published var currentRecordingMode: CurrentRecordingMode = .directPaste
    @Published var recordingStartedAt: Date?
    @Published var needsModelSetup = false

    // Permissions
    @Published var hasMicrophonePermission = false
    @Published var hasAccessibilityPermission = false
    @Published var hasAutomationPermission = false

    // API
    @Published var hasAPIKey = false
    @Published var hasCustomKey = false

    // Errors
    @Published var lastError: String?
    @Published var showError = false

    // Review mode
    @Published var pendingTranscription: String?
    @Published var showReviewWindow = false

    // Ready to use (either offline mode or has API key)
    var isReadyToUse: Bool {
        SettingsManager.shared.offlineModeEnabled || hasAPIKey
    }

    init() {
        hasAPIKey = KeychainService.shared.hasAPIKey
        updateUsageInfo()
    }

    func updateUsageInfo() {
        hasCustomKey = KeychainService.shared.hasCustomKey
    }

    func showErrorMessage(_ message: String) {
        lastError = message
        showError = true
    }
}
