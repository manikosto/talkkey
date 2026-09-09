import SwiftUI
import Combine

enum CurrentRecordingMode: CaseIterable {
    case directPaste
    case review
    case translation

    /// Stable identifier for storing a key's assigned action.
    var storageKey: String {
        switch self {
        case .directPaste: return "directPaste"
        case .review: return "review"
        case .translation: return "translation"
        }
    }

    init?(storageKey: String) {
        switch storageKey {
        case "directPaste": self = .directPaste
        case "review": self = .review
        case "translation": self = .translation
        default: return nil
        }
    }

    var shortName: String {
        switch self {
        case .directPaste: return "Paste"
        case .review: return "Review"
        case .translation: return "Translate"
        }
    }

    /// Review and Translate are Pro; plain dictation is always available.
    var requiresPro: Bool { self != .directPaste }

    var displayText: String {
        switch self {
        case .directPaste: return "Recording"
        case .review: return "Recording (Review)"
        case .translation: return "Translating"
        }
    }

    var indicatorColor: Color {
        switch self {
        case .directPaste: return .red
        case .review: return .orange
        case .translation: return .blue
        }
    }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    // Recording state
    @Published var isRecording = false
    @Published var isTranscribing = false
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
