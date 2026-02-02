import Foundation

class RewriteService {
    static let shared = RewriteService()

    func rewrite(text: String, style: RewriteStyle, model: GPTModel) async throws -> String {
        guard let apiKey = KeychainService.shared.getAPIKey() else {
            throw RewriteError.noAPIKey
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = """
        You are a text rewriting assistant. Your task is to rewrite the user's text according to the specified style.
        \(style.prompt)

        Important rules:
        - Preserve the original language of the text
        - Do not add explanations or meta-commentary
        - Return only the rewritten text
        - Maintain the original meaning and key information
        """

        let body: [String: Any] = [
            "model": model.apiName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.7,
            "max_tokens": 2000
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RewriteError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw RewriteError.invalidAPIKey
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw RewriteError.apiError(errorResponse.error.message)
            }
            throw RewriteError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let chatResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw RewriteError.emptyResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Response Types

struct ChatCompletionResponse: Codable {
    let choices: [ChatChoice]
}

struct ChatChoice: Codable {
    let message: ChatMessage
}

struct ChatMessage: Codable {
    let content: String
}

// MARK: - Errors

enum RewriteError: LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case invalidResponse
    case emptyResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured"
        case .invalidAPIKey:
            return "Invalid API key"
        case .invalidResponse:
            return "Invalid response from server"
        case .emptyResponse:
            return "Empty response from server"
        case .apiError(let message):
            return message
        }
    }
}
