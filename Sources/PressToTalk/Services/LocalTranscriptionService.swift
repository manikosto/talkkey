import Foundation
import WhisperKit

enum LocalTranscriptionError: LocalizedError {
    case modelNotLoaded
    case transcriptionFailed(String)
    case modelDownloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model is not loaded"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .modelDownloadFailed(let message):
            return "Model download failed: \(message)"
        }
    }
}

@MainActor
class LocalTranscriptionService: ObservableObject {
    static let shared = LocalTranscriptionService()

    @Published var isModelLoaded = false
    @Published var isModelLoading = false  // Loading model into memory
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var selectedModel: String = "small"  // Default to bundled model

    private var whisperKit: WhisperKit?

    // The bundled model that comes with the app
    static let bundledModel = "small"

    // Available models (sorted by size/quality)
    let availableModels = [
        "tiny",      // ~39MB, fastest
        "base",      // ~74MB, fast
        "small",     // ~244MB, good balance (bundled)
        "medium",    // ~769MB, high quality
        "large-v3"   // ~1.5GB, best quality
    ]

    // User-friendly model names
    var modelDisplayName: [String: String] {
        [
            "tiny": "Turbo",
            "base": "Fast",
            "small": "Balanced (Included)",
            "medium": "Accurate",
            "large-v3": "Most Accurate"
        ]
    }

    private init() {
        // Load saved model preference, but validate it's available
        if let savedModel = UserDefaults.standard.string(forKey: "selectedWhisperModel") {
            // Only use saved model if it's bundled or downloaded
            if savedModel == Self.bundledModel || isModelDownloadedSync(savedModel) {
                selectedModel = savedModel
            } else {
                // Reset to bundled model if saved model not available
                selectedModel = Self.bundledModel
                UserDefaults.standard.set(Self.bundledModel, forKey: "selectedWhisperModel")
            }
        }

        // If bundled model exists, mark as loading immediately (will auto-load on startup)
        if hasBundledModel {
            isModelLoading = true
        }
    }

    // Sync version for init (can't use async in init)
    private func isModelDownloadedSync(_ model: String) -> Bool {
        let modelPath = modelDirectory.appendingPathComponent("openai_whisper-\(model)")
        return FileManager.default.fileExists(atPath: modelPath.path)
    }

    // Path to bundled model in app resources
    var bundledModelPath: URL? {
        // In app bundle: Resources/PressToTalk_PressToTalk.bundle/openai_whisper-small
        if let bundlePath = Bundle.main.resourceURL?
            .appendingPathComponent("PressToTalk_PressToTalk.bundle")
            .appendingPathComponent("openai_whisper-small"),
           FileManager.default.fileExists(atPath: bundlePath.path) {
            return bundlePath
        }
        // Fallback: direct path (for CLI/debug builds)
        if let executableURL = Bundle.main.executableURL {
            let bundlePath = executableURL.deletingLastPathComponent()
                .appendingPathComponent("PressToTalk_PressToTalk.bundle")
                .appendingPathComponent("openai_whisper-small")
            if FileManager.default.fileExists(atPath: bundlePath.path) {
                return bundlePath
            }
        }
        return nil
    }

    // Path for downloaded models (Application Support)
    var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelDir = appSupport.appendingPathComponent("TalkKey/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        return modelDir
    }

    // Check if bundled model exists
    var hasBundledModel: Bool {
        guard let path = bundledModelPath else { return false }
        return FileManager.default.fileExists(atPath: path.path)
    }

    func isModelDownloaded(_ model: String) -> Bool {
        // Bundled model is always available
        if model == Self.bundledModel && hasBundledModel {
            return true
        }
        // Check downloaded models
        let modelPath = modelDirectory.appendingPathComponent("openai_whisper-\(model)")
        return FileManager.default.fileExists(atPath: modelPath.path)
    }

    func loadModel(_ model: String? = nil) async throws {
        let modelToLoad = model ?? selectedModel

        // If already loaded with same model, skip
        if isModelLoaded && selectedModel == modelToLoad {
            return
        }

        let isBundled = modelToLoad == Self.bundledModel && hasBundledModel

        // Set appropriate loading state
        if isBundled {
            isModelLoading = true  // Loading bundled model into memory
        } else {
            isDownloading = true   // Downloading from internet
        }
        downloadProgress = 0

        do {
            let config: WhisperKitConfig

            // Use bundled model if available
            if isBundled, let bundledPath = bundledModelPath {
                print("Loading bundled model from: \(bundledPath.path)")
                config = WhisperKitConfig(
                    modelFolder: bundledPath.path,
                    verbose: false,
                    prewarm: true
                )
            } else {
                // Download other models
                print("Downloading model: \(modelToLoad)")
                config = WhisperKitConfig(
                    model: modelToLoad,
                    downloadBase: modelDirectory,
                    verbose: false,
                    prewarm: true
                )
            }

            whisperKit = try await WhisperKit(config)
            isModelLoaded = true
            selectedModel = modelToLoad
            UserDefaults.standard.set(modelToLoad, forKey: "selectedWhisperModel")

            isModelLoading = false
            isDownloading = false
            downloadProgress = 1.0
        } catch {
            isModelLoading = false
            isDownloading = false
            throw LocalTranscriptionError.modelDownloadFailed(error.localizedDescription)
        }
    }

    // Alias for backward compatibility
    func downloadModel(_ model: String) async throws {
        try await loadModel(model)
    }

    func transcribe(audioURL: URL, translateToEnglish: Bool = false) async throws -> String {
        guard let whisperKit = whisperKit, isModelLoaded else {
            // Try to load model first
            try await loadModel()
            guard let wk = self.whisperKit else {
                throw LocalTranscriptionError.modelNotLoaded
            }
            return try await transcribeWith(wk, audioURL: audioURL, translateToEnglish: translateToEnglish)
        }

        return try await transcribeWith(whisperKit, audioURL: audioURL, translateToEnglish: translateToEnglish)
    }

    private func transcribeWith(_ whisperKit: WhisperKit, audioURL: URL, translateToEnglish: Bool = false) async throws -> String {
        let settings = SettingsManager.shared

        // Use .translate task for instant English translation via Whisper
        let task: DecodingTask = translateToEnglish ? .translate : .transcribe

        // For translation: don't set language - let Whisper auto-detect source and translate to English
        // For transcription: use user's language preference
        let languageCode: String?
        if translateToEnglish {
            languageCode = nil  // Auto-detect for translation
        } else {
            let language = settings.selectedLanguage
            languageCode = language == .auto ? nil : language.rawValue
        }

        // Configure decoding options
        let options = DecodingOptions(
            task: task,
            language: languageCode
        )

        // Debug
        let debugMsg = "WHISPER: task=\(task), lang=\(String(describing: languageCode)), selectedLang=\(settings.selectedLanguage.rawValue)\n"
        if let data = debugMsg.data(using: .utf8) {
            let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("talkkey_debug.log")
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: logURL)
            }
        }

        let results = try await whisperKit.transcribe(audioPath: audioURL.path, decodeOptions: options)

        guard let result = results.first else {
            throw LocalTranscriptionError.transcriptionFailed("No results returned")
        }

        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unloadModel() {
        whisperKit = nil
        isModelLoaded = false
    }

    func deleteModel(_ model: String) throws {
        let modelPath = modelDirectory.appendingPathComponent("openai_whisper-\(model)")
        if FileManager.default.fileExists(atPath: modelPath.path) {
            try FileManager.default.removeItem(at: modelPath)
        }

        // If we deleted the current model, unload it
        if model == selectedModel {
            unloadModel()
        }
    }

    var modelSizeDescription: [String: String] {
        [
            "tiny": "39 MB",
            "base": "74 MB",
            "small": "244 MB",
            "medium": "769 MB",
            "large-v3": "1.5 GB"
        ]
    }

    var modelQualityDescription: [String: String] {
        [
            "tiny": "Fastest, basic quality",
            "base": "Fast, good quality",
            "small": "Included - great balance",
            "medium": "More accurate, slower",
            "large-v3": "Best accuracy, slowest"
        ]
    }
}
