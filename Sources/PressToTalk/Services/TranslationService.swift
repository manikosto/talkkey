import Foundation
import NaturalLanguage

/// Translates text, on device when possible and through OpenAI otherwise.
///
/// Order: Apple's on-device model (macOS 15+, pack installed, setting on),
/// then OpenAI when an API key exists. A language pack that only needs
/// downloading is offered to the user rather than skipped, because after that
/// one prompt every later translation is private, offline and free.
class TranslationService {
    static let shared = TranslationService()

    private let chatEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    /// Which engine produced a translation, for the result toast.
    enum Engine {
        case onDevice
        case openAI

        var label: String {
            switch self {
            case .onDevice: return "on this Mac"
            case .openAI: return "via OpenAI"
            }
        }
    }

    struct Result {
        let text: String
        let engine: Engine
    }

    func translate(text: String, to targetLanguage: TranslationLanguage) async throws -> String {
        try await translateDetailed(text: text, to: targetLanguage).text
    }

    func translateDetailed(text: String, to targetLanguage: TranslationLanguage) async throws -> Result {
        let hasAPIKey = KeychainService.shared.getAPIKey() != nil

        if SettingsManager.shared.onDeviceTranslationEnabled, #available(macOS 15.0, *) {
            let translator = await OnDeviceTranslator.shared
            switch await translator.availability(for: text, to: targetLanguage) {
            case .installed:
                let translated = try await translator.translate(text, to: targetLanguage, allowDownload: false)
                return Result(text: translated, engine: .onDevice)
            case .needsDownload:
                do {
                    let translated = try await translator.translate(text, to: targetLanguage, allowDownload: true)
                    return Result(text: translated, engine: .onDevice)
                } catch {
                    // Declined or failed download: OpenAI if it can, else say why.
                    guard hasAPIKey else { throw TranslationError.languageNotInstalled(targetLanguage) }
                }
            case .unsupported:
                guard hasAPIKey else { throw TranslationError.unsupportedOnDevice(targetLanguage) }
            }
        }

        let translated = try await translateViaOpenAI(text: text, to: targetLanguage)
        return Result(text: translated, engine: .openAI)
    }

    /// The language the text is most likely written in, if it can be told.
    func detectLanguage(of text: String) -> TranslationLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage,
              let confidence = recognizer.languageHypotheses(withMaximum: 1)[dominant],
              confidence > 0.6 else {
            return nil
        }
        return TranslationLanguage.matching(languageCode: dominant.rawValue)
    }

    private func translateViaOpenAI(text: String, to targetLanguage: TranslationLanguage) async throws -> String {
        guard let apiKey = KeychainService.shared.getAPIKey() else {
            throw TranslationError.missingAPIKey
        }

        let prompt = """
        Translate the following text to \(targetLanguage.fullName).
        Only return the translation, nothing else.
        Preserve the original formatting and tone.

        Text to translate:
        \(text)
        """

        var request = URLRequest(url: chatEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let model = SettingsManager.shared.selectedModel.apiName

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are a professional translator. Translate accurately while preserving tone and style."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "max_tokens": 2000
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw TranslationError.apiError(message)
            }
            throw TranslationError.apiError("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslationError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TranslationError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)
    case languageNotInstalled(TranslationLanguage)
    case unsupportedOnDevice(TranslationLanguage)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key not found"
        case .invalidResponse:
            return "Invalid response from translation service"
        case .apiError(let message):
            return "Translation error: \(message)"
        case .languageNotInstalled(let language):
            return "\(language.fullName) isn't downloaded for on-device translation. Accept the download when macOS offers it, or add an OpenAI API key in Settings."
        case .unsupportedOnDevice(let language):
            return "This Mac can't translate to \(language.fullName) on device. Add an OpenAI API key in Settings to translate online."
        }
    }
}
