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

    /// Recently used models kept in memory so switching between per-mode
    /// models doesn't pay a multi-second reload on every recording.
    private var modelCache: [String: WhisperKit] = [:]
    private var cacheOrder: [String] = []
    /// large-v3 alone is well over a gigabyte resident; two is the most worth
    /// holding on a typical machine.
    private let maxCachedModels = 2

    // Available models (ordered by size)
    let availableModels = [
        "tiny",                          // ~39 MB
        "base",                          // ~74 MB
        "small",                         // ~244 MB
        "large-v3-v20240930_626MB",      // ~626 MB — large-v3-turbo, quantized
        "medium",                        // ~769 MB
        "large-v3-v20240930",            // ~1.6 GB — large-v3-turbo, full
        "large-v3"                       // ~1.5 GB — best quality, slowest
    ]

    /// Turbo is distilled for transcription only — it was never trained on the
    /// translate task, so it must not be used for speech translation.
    static let transcribeOnlyModels: Set<String> = [
        "large-v3-v20240930_626MB",
        "large-v3-v20240930"
    ]

    func supportsTranslation(_ model: String) -> Bool {
        !Self.transcribeOnlyModels.contains(model)
    }

    /// The model recommended for most people: near large-v3 accuracy at a
    /// fraction of the size and time.
    static let recommendedModel = "large-v3-v20240930_626MB"

    // User-friendly model names
    var modelDisplayName: [String: String] {
        [
            "tiny": "Tiny",
            "base": "Fast",
            "small": "Balanced",
            "large-v3-v20240930_626MB": "Turbo",
            "medium": "Accurate",
            "large-v3-v20240930": "Turbo HQ",
            "large-v3": "Maximum"
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

    // WhisperKit stores models in a nested path under downloadBase
    private var whisperKitModelBase: URL {
        modelDirectory.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
    }

    // Sync version for init
    private func isModelDownloadedSync(_ model: String) -> Bool {
        let modelPath = whisperKitModelBase.appendingPathComponent("openai_whisper-\(model)")
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
        let modelPath = whisperKitModelBase.appendingPathComponent("openai_whisper-\(model)")
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
            let engine = try await engine(for: modelToLoad)

            whisperKit = engine
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

    /// Returns a ready engine for `model`, reusing a cached one when possible.
    private func engine(for model: String) async throws -> WhisperKit {
        if let cached = modelCache[model] {
            touchCache(model)
            return cached
        }

        let config = WhisperKitConfig(
            model: model,
            downloadBase: modelDirectory,
            verbose: false,
            prewarm: true
        )
        let engine = try await WhisperKit(config)

        modelCache[model] = engine
        touchCache(model)
        evictIfNeeded()
        return engine
    }

    private func touchCache(_ model: String) {
        cacheOrder.removeAll { $0 == model }
        cacheOrder.append(model)
    }

    private func evictIfNeeded() {
        while cacheOrder.count > maxCachedModels {
            let victim = cacheOrder.removeFirst()
            // Never evict the engine that is currently in use.
            if victim == selectedModel { cacheOrder.append(victim); break }
            modelCache[victim] = nil
        }
    }

    /// Resolves and loads the model a given mode should use, falling back to
    /// the main model when the mode has no override or its model isn't
    /// installed. Returns the engine to transcribe with.
    private func engineForCurrentMode(translating: Bool) async throws -> WhisperKit {
        let settings = SettingsManager.shared
        var wanted = settings.modelOverride(for: settings.activeTranscriptionMode) ?? selectedModel

        // Turbo can't translate; silently fall back rather than emit garbage.
        if translating && !supportsTranslation(wanted) {
            wanted = availableModels.first { isModelDownloaded($0) && supportsTranslation($0) } ?? wanted
        }

        guard isModelDownloaded(wanted) else {
            // Override points at something not installed — use what we have.
            guard let engine = whisperKit else { throw LocalTranscriptionError.modelNotLoaded }
            return engine
        }

        if wanted == selectedModel, let engine = whisperKit { return engine }
        return try await engine(for: wanted)
    }

    func downloadModel(_ model: String) async throws {
        try await loadModel(model)
    }

    struct TranscribeResult {
        let text: String
        let detectedLanguage: String?
    }

    func transcribe(audioURL: URL, translateToEnglish: Bool = false) async throws -> TranscribeResult {
        guard hasAnyModel else { throw LocalTranscriptionError.noModelInstalled }

        if whisperKit == nil || !isModelLoaded {
            try await loadModel()
        }

        // Each mode may pin its own model; this resolves and loads it, reusing
        // a cached engine when the mode was used recently.
        let engine = try await engineForCurrentMode(translating: translateToEnglish)
        return try await transcribeWith(engine, audioURL: audioURL, translateToEnglish: translateToEnglish)
    }

    private func transcribeWith(_ whisperKit: WhisperKit, audioURL: URL, translateToEnglish: Bool = false) async throws -> TranscribeResult {
        let settings = SettingsManager.shared

        if !translateToEnglish && settings.effectiveLanguage == .auto {
            return try await transcribeAutoDetect(whisperKit, audioURL: audioURL)
        }

        let task: DecodingTask = translateToEnglish ? .translate : .transcribe
        let languageCode: String? = translateToEnglish ? nil : settings.effectiveLanguage.rawValue

        let options = DecodingOptions(
            task: task,
            language: languageCode,
            usePrefillPrompt: true,
            detectLanguage: false,
            promptTokens: primingTokens(whisperKit)
        )

        let results = try await whisperKit.transcribe(audioPath: audioURL.path, decodeOptions: options)

        guard let result = results.first else {
            throw LocalTranscriptionError.transcriptionFailed("No results returned")
        }

        return TranscribeResult(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            detectedLanguage: result.language
        )
    }

    /// Auto-detect with disambiguation.
    ///
    /// Whisper has a nasty failure mode: when the detected language token is
    /// wrong (e.g. accented English detected as Russian), `.transcribe` silently
    /// *translates* the speech into the detected language instead of writing
    /// down what was said. So when detection is not confident, we decode with
    /// both top candidates and keep the output the model itself was more sure
    /// about (higher average token log-probability).
    private func transcribeAutoDetect(_ whisperKit: WhisperKit, audioURL: URL) async throws -> TranscribeResult {
        let supported = Set(WhisperLanguage.allCases.map(\.rawValue)).subtracting(["auto"])
        let detection = try await whisperKit.detectLanguage(audioPath: audioURL.path)

        // Rank candidates within the languages the app actually offers —
        // this alone removes most of the long-tail misdetections.
        let ranked = detection.langProbs
            .filter { supported.contains($0.key) }
            .sorted { $0.value > $1.value }

        let best = ranked.first?.key ?? detection.language
        let bestProb = ranked.first?.value ?? 0
        let runnerUp = ranked.dropFirst().first

        let bestResult = try await decode(whisperKit, audioURL: audioURL, language: best)

        if let runnerUp, bestProb < 0.8, runnerUp.value > 0.1 {
            let altResult = try await decode(whisperKit, audioURL: audioURL, language: runnerUp.key)
            if decodeConfidence(altResult) > decodeConfidence(bestResult) {
                return TranscribeResult(
                    text: altResult.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    detectedLanguage: runnerUp.key
                )
            }
        }

        return TranscribeResult(
            text: bestResult.text.trimmingCharacters(in: .whitespacesAndNewlines),
            detectedLanguage: best
        )
    }

    /// Custom-vocabulary terms encoded for `DecodingOptions.promptTokens`,
    /// which biases the decoder toward spellings it would otherwise mangle.
    private func primingTokens(_ whisperKit: WhisperKit) -> [Int]? {
        guard let prompt = DictionaryManager.shared.primingPrompt(),
              let tokenizer = whisperKit.tokenizer else { return nil }
        let tokens = tokenizer.encode(text: " " + prompt)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return tokens.isEmpty ? nil : tokens
    }

    private func decode(_ whisperKit: WhisperKit, audioURL: URL, language: String) async throws -> TranscriptionResult {
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            usePrefillPrompt: true,
            detectLanguage: false,
            promptTokens: primingTokens(whisperKit)
        )
        let results = try await whisperKit.transcribe(audioPath: audioURL.path, decodeOptions: options)
        guard let result = results.first else {
            throw LocalTranscriptionError.transcriptionFailed("No results returned")
        }
        return result
    }

    private func decodeConfidence(_ result: TranscriptionResult) -> Float {
        let segments = result.segments
        guard !segments.isEmpty,
              !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return -.greatestFiniteMagnitude
        }
        return segments.map(\.avgLogprob).reduce(0, +) / Float(segments.count)
    }

    func transcribePartial(audioSamples: [Float]) async throws -> String {
        guard let whisperKit = whisperKit, isModelLoaded else {
            throw LocalTranscriptionError.modelNotLoaded
        }

        let settings = SettingsManager.shared
        let language = settings.effectiveLanguage
        let languageCode: String? = language == .auto ? nil : language.rawValue

        let options = DecodingOptions(
            task: .transcribe,
            language: languageCode,
            usePrefillPrompt: true,
            detectLanguage: languageCode == nil
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
        // Unload first: deleting the files under a loaded model leaves
        // WhisperKit holding references to weights that no longer exist.
        if model == selectedModel && isModelLoaded {
            unloadModel()
        }

        let modelPath = whisperKitModelBase.appendingPathComponent("openai_whisper-\(model)")
        if FileManager.default.fileExists(atPath: modelPath.path) {
            try FileManager.default.removeItem(at: modelPath)
        }

        // Fall back to another installed model so offline mode keeps working.
        if model == selectedModel, let next = availableModels.first(where: { isModelDownloaded($0) }) {
            selectedModel = next
            UserDefaults.standard.set(next, forKey: "selectedWhisperModel")
        }

        objectWillChange.send()
    }

    /// Bytes a downloaded model occupies, or nil when it isn't installed.
    func diskSize(of model: String) -> Int64? {
        let path = whisperKitModelBase.appendingPathComponent("openai_whisper-\(model)")
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }

        guard let files = FileManager.default.enumerator(
            at: path,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        ) else { return nil }

        var total: Int64 = 0
        for case let url as URL in files {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    var totalDiskUsage: Int64 {
        availableModels.compactMap { diskSize(of: $0) }.reduce(0, +)
    }

    var installedModels: [String] {
        availableModels.filter { isModelDownloaded($0) }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    var modelSizeDescription: [String: String] {
        [
            "tiny": "39 MB",
            "base": "74 MB",
            "small": "244 MB",
            "large-v3-v20240930_626MB": "626 MB",
            "medium": "769 MB",
            "large-v3-v20240930": "1.6 GB",
            "large-v3": "1.5 GB"
        ]
    }

    var modelQualityDescription: [String: String] {
        [
            "tiny": "Fastest, rough quality",
            "base": "Fast, basic quality",
            "small": "Weak on Russian and other inflected languages",
            "large-v3-v20240930_626MB": "Near-best accuracy, fast — transcription only",
            "medium": "Good accuracy, slower",
            "large-v3-v20240930": "Near-best accuracy — transcription only",
            "large-v3": "Best accuracy, handles translation, slowest"
        ]
    }
}
