import Foundation
import WhisperKit

enum LocalTranscriptionError: LocalizedError {
    case modelNotLoaded
    case noModelInstalled
    case transcriptionFailed(String)
    case modelDownloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model is not loaded"
        case .noModelInstalled:
            return "No speech recognition model installed. Please select and download a model in Settings."
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
    @Published var isModelLoading = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var selectedModel: String = "small"

    private var whisperKit: WhisperKit?

    // Available models (sorted by size/quality)
    let availableModels = [
        "tiny",      // ~39MB, fastest
        "base",      // ~74MB, fast
        "small",     // ~244MB, good balance
        "medium",    // ~769MB, high quality
        "large-v3"   // ~1.5GB, best quality
    ]

    // User-friendly model names
    var modelDisplayName: [String: String] {
        [
            "tiny": "Turbo",
            "base": "Fast",
            "small": "Balanced",
            "medium": "Accurate",
            "large-v3": "Most Accurate"
        ]
    }

    private init() {
        // Load saved model preference, validate it's downloaded
        if let savedModel = UserDefaults.standard.string(forKey: "selectedWhisperModel"),
           isModelDownloadedSync(savedModel) {
            selectedModel = savedModel
        } else {
            // Find any downloaded model
            if let firstAvailable = availableModels.first(where: { isModelDownloadedSync($0) }) {
                selectedModel = firstAvailable
            }
            // Otherwise keep default "small" — user will need to download
        }
    }

    // Sync version for init
    private func isModelDownloadedSync(_ model: String) -> Bool {
        let modelPath = modelDirectory.appendingPathComponent("openai_whisper-\(model)")
        return FileManager.default.fileExists(atPath: modelPath.path)
    }

    // Path for downloaded models (Application Support)
    var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelDir = appSupport.appendingPathComponent("TalkKey/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        return modelDir
    }

    // Check if ANY model is available (downloaded)
    var hasAnyModel: Bool {
        availableModels.contains { isModelDownloadedSync($0) }
    }

    func isModelDownloaded(_ model: String) -> Bool {
        let modelPath = modelDirectory.appendingPathComponent("openai_whisper-\(model)")
        return FileManager.default.fileExists(atPath: modelPath.path)
    }

    func loadModel(_ model: String? = nil) async throws {
        let modelToLoad = model ?? selectedModel

        // If already loaded with same model, skip
        if isModelLoaded && selectedModel == modelToLoad {
            return
        }

        let isAlreadyDownloaded = isModelDownloaded(modelToLoad)

        if isAlreadyDownloaded {
            isModelLoading = true
        } else {
            isDownloading = true
        }
        downloadProgress = 0

        do {
            let config = WhisperKitConfig(
                model: modelToLoad,
                downloadBase: modelDirectory,
                verbose: false,
                prewarm: true
            )

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

    func downloadModel(_ model: String) async throws {
        try await loadModel(model)
    }

    func transcribe(audioURL: URL, translateToEnglish: Bool = false) async throws -> String {
        guard let whisperKit = whisperKit, isModelLoaded else {
            if !hasAnyModel {
                throw LocalTranscriptionError.noModelInstalled
            }
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

        let task: DecodingTask = translateToEnglish ? .translate : .transcribe

        let languageCode: String?
        if translateToEnglish {
            languageCode = nil
        } else {
            let language = settings.selectedLanguage
            languageCode = language == .auto ? nil : language.rawValue
        }

        let options = DecodingOptions(
            task: task,
            language: languageCode
        )

        let results = try await whisperKit.transcribe(audioPath: audioURL.path, decodeOptions: options)

        guard let result = results.first else {
            throw LocalTranscriptionError.transcriptionFailed("No results returned")
        }

        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func transcribePartial(audioSamples: [Float]) async throws -> String {
        guard let whisperKit = whisperKit, isModelLoaded else {
            throw LocalTranscriptionError.modelNotLoaded
        }

        let settings = SettingsManager.shared
        let language = settings.selectedLanguage
        let languageCode: String? = language == .auto ? nil : language.rawValue

        let options = DecodingOptions(
            task: .transcribe,
            language: languageCode
        )

        let results = try await whisperKit.transcribe(audioArray: audioSamples, decodeOptions: options)
        guard let result = results.first else {
            return ""
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
            "small": "Great balance of speed and quality",
            "medium": "More accurate, slower",
            "large-v3": "Best accuracy, slowest"
        ]
    }
}
