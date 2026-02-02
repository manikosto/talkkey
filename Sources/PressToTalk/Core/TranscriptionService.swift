import Foundation
import Network

class TranscriptionService {
    static let shared = TranscriptionService()

    private let whisperEndpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true

    init() {
        // Start network monitoring
        networkMonitor.pathUpdateHandler = { [weak self] path in
            self?.isNetworkAvailable = (path.status == .satisfied)
        }
        networkMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    func transcribe(audioURL: URL, translateTo: TranslationLanguage? = nil) async throws -> String {
        let settings = SettingsManager.shared

        // Step 1: Transcribe (offline or online with auto-fallback)
        var result: String
        if settings.offlineModeEnabled {
            result = try await transcribeOffline(audioURL: audioURL, translateToEnglish: translateTo == .english)
        } else {
            // Cloud mode - but check if offline fallback is available
            let localService = await LocalTranscriptionService.shared
            let canFallbackToOffline = await localService.isModelLoaded

            if !isNetworkAvailable && canFallbackToOffline {
                // No internet, but we have local model - auto fallback
                print("No internet connection, falling back to offline transcription")
                result = try await transcribeOffline(audioURL: audioURL, translateToEnglish: translateTo == .english)
            } else {
                // Try cloud transcription
                do {
                    result = try await transcribeOnline(audioURL: audioURL)
                } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                    // Network error - try offline fallback if available
                    if canFallbackToOffline {
                        print("Network error, falling back to offline transcription")
                        result = try await transcribeOffline(audioURL: audioURL, translateToEnglish: translateTo == .english)
                    } else {
                        throw error
                    }
                }
            }
        }

        // Step 2: Translate if requested
        // - For offline mode: English translation is handled by Whisper's translate task above
        // - For cloud mode: always use TranslationService for any language
        if let targetLanguage = translateTo {
            // Skip translation only if offline mode AND target is English (already translated by Whisper)
            let skipTranslation = settings.offlineModeEnabled && targetLanguage == .english
            if !skipTranslation {
                result = try await TranslationService.shared.translate(
                    text: result,
                    to: targetLanguage
                )
            }
        }

        return result
    }

    private func transcribeOffline(audioURL: URL, translateToEnglish: Bool = false) async throws -> String {
        let localService = await LocalTranscriptionService.shared
        let result = try await localService.transcribe(audioURL: audioURL, translateToEnglish: translateToEnglish)

        // Clean up temp file
        try? FileManager.default.removeItem(at: audioURL)

        return result
    }

    private func transcribeOnline(audioURL: URL) async throws -> String {
        guard let apiKey = KeychainService.shared.getAPIKey() else {
            throw TranscriptionError.missingAPIKey
        }

        // Read audio file
        let audioData = try Data(contentsOf: audioURL)

        // Create multipart form data request
        let boundary = UUID().uuidString
        var request = URLRequest(url: whisperEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        var body = Data()

        // Add model field
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.append("whisper-1\r\n")

        // Add language field (if not auto-detect)
        let language = SettingsManager.shared.selectedLanguage
        if language != .auto {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            body.append("\(language.rawValue)\r\n")
        }

        // Add audio file (m4a format)
        let filename = audioURL.lastPathComponent
        let mimeType = filename.hasSuffix(".m4a") ? "audio/m4a" : "audio/wav"
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")

        // Close boundary
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw TranscriptionError.apiError(errorResponse.error.message)
            }
            throw TranscriptionError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(WhisperResponse.self, from: data)

        // Clean up temp file
        try? FileManager.default.removeItem(at: audioURL)

        return result.text
    }
}

// MARK: - Models

struct WhisperResponse: Codable {
    let text: String
}

struct OpenAIErrorResponse: Codable {
    let error: OpenAIError
}

struct OpenAIError: Codable {
    let message: String
    let type: String?
}

// MARK: - Errors

enum TranscriptionError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key not configured. Please add it in Settings."
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let message):
            return "API Error: \(message)"
        }
    }
}

// MARK: - Data Extension

extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
