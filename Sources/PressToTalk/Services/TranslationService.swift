import Foundation

class TranslationService {
    static let shared = TranslationService()

    private let chatEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    func translate(text: String, to targetLanguage: TranslationLanguage) async throws -> String {
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

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key not found"
        case .invalidResponse:
            return "Invalid response from translation service"
        case .apiError(let message):
            return "Translation error: \(message)"
        }
    }
}
