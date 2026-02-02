import SwiftUI
import Combine

enum CurrentRecordingMode {
    case directPaste
    case review
    case translation

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
    @Published var audioLevels: [CGFloat] = Array(repeating: 0.05, count: 50)

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

    func updateAudioLevel(_ level: CGFloat) {
        audioLevels.removeFirst()
        audioLevels.append(level)
    }

    func resetAudioLevels() {
        audioLevels = Array(repeating: 0.05, count: 50)
    }
}
