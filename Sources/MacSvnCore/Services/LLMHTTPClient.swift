import Foundation

public struct AIHTTPRequest: Equatable, Sendable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data

    public init(url: URL, method: String, headers: [String: String], body: Data) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct AIHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol AIHTTPTransport: Sendable {
    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse
}

public struct URLSessionAIHTTPTransport: AIHTTPTransport, Sendable {
    public init() {}

    public func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = request.body

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMClientError.invalidResponse("Missing HTTPURLResponse.")
        }
        return AIHTTPResponse(statusCode: httpResponse.statusCode, data: data)
    }
}

public enum LLMClientError: Error, Equatable, Sendable {
    case invalidBaseURL(String)
    case missingAPIKey(String)
    case httpError(statusCode: Int, body: String)
    case invalidResponse(String)
}

public actor LLMHTTPClient: LLMChatting {
    private let transport: any AIHTTPTransport
    private let apiKeyStore: any AIAPIKeyStoring
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        transport: any AIHTTPTransport = URLSessionAIHTTPTransport(),
        apiKeyStore: any AIAPIKeyStoring = AIKeychainStore()
    ) {
        self.transport = transport
        self.apiKeyStore = apiKeyStore
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func chat(provider: AIProvider, messages: [AILLMMessage]) async throws -> AILLMResponse {
        let request: AIHTTPRequest
        switch provider.kind {
        case .openAICompatible:
            request = try await openAICompatibleRequest(provider: provider, messages: messages)
        case .anthropic:
            request = try await anthropicRequest(provider: provider, messages: messages)
        case .ollama:
            request = try ollamaRequest(provider: provider, messages: messages)
        }

        let response = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw LLMClientError.httpError(
                statusCode: response.statusCode,
                body: String(decoding: response.data, as: UTF8.self)
            )
        }

        switch provider.kind {
        case .openAICompatible:
            return try parseOpenAICompatibleResponse(response.data)
        case .anthropic:
            return try parseAnthropicResponse(response.data)
        case .ollama:
            return try parseOllamaResponse(response.data)
        }
    }

    private func openAICompatibleRequest(provider: AIProvider, messages: [AILLMMessage]) async throws -> AIHTTPRequest {
        let url = try endpoint(baseURL: provider.baseURL, path: ["chat", "completions"])
        var headers = defaultHeaders()
        if let apiKey = try await apiKeyIfConfigured(provider.apiKeyRef) {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        let body = OpenAIRequest(
            model: provider.model,
            messages: messages.map(LLMMessageDTO.init),
            temperature: provider.temperature,
            maxTokens: provider.maxTokens
        )
        return AIHTTPRequest(url: url, method: "POST", headers: headers, body: try encoder.encode(body))
    }

    private func anthropicRequest(provider: AIProvider, messages: [AILLMMessage]) async throws -> AIHTTPRequest {
        let url = try endpoint(baseURL: provider.baseURL, path: ["v1", "messages"])
        var headers = defaultHeaders()
        headers["anthropic-version"] = "2023-06-01"
        if let apiKey = try await apiKeyIfConfigured(provider.apiKeyRef) {
            headers["x-api-key"] = apiKey
        }
        let system = messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n")
        let requestMessages = messages
            .filter { $0.role != .system }
            .map(LLMMessageDTO.init)
        let body = AnthropicRequest(
            model: provider.model,
            maxTokens: provider.maxTokens,
            temperature: provider.temperature,
            system: system.isEmpty ? nil : system,
            messages: requestMessages
        )
        return AIHTTPRequest(url: url, method: "POST", headers: headers, body: try encoder.encode(body))
    }

    private func ollamaRequest(provider: AIProvider, messages: [AILLMMessage]) throws -> AIHTTPRequest {
        let url = try endpoint(baseURL: provider.baseURL, path: ["api", "chat"])
        let body = OllamaRequest(
            model: provider.model,
            messages: messages.map(LLMMessageDTO.init),
            stream: false,
            options: OllamaOptions(
                temperature: provider.temperature,
                numPredict: provider.maxTokens
            )
        )
        return AIHTTPRequest(url: url, method: "POST", headers: defaultHeaders(), body: try encoder.encode(body))
    }

    private func parseOpenAICompatibleResponse(_ data: Data) throws -> AILLMResponse {
        do {
            let response = try decoder.decode(OpenAIResponse.self, from: data)
            let content = response.choices?.first?.message.content
            return try makeResponse(
                content: content,
                promptTokens: response.usage?.promptTokens,
                completionTokens: response.usage?.completionTokens
            )
        } catch let error as LLMClientError {
            throw error
        } catch {
            throw LLMClientError.invalidResponse(String(describing: error))
        }
    }

    private func parseAnthropicResponse(_ data: Data) throws -> AILLMResponse {
        do {
            let response = try decoder.decode(AnthropicResponse.self, from: data)
            let text = response.content?
                .filter { $0.type == "text" }
                .map(\.text)
                .joined(separator: "\n")
            return try makeResponse(
                content: text,
                promptTokens: response.usage?.inputTokens,
                completionTokens: response.usage?.outputTokens
            )
        } catch let error as LLMClientError {
            throw error
        } catch {
            throw LLMClientError.invalidResponse(String(describing: error))
        }
    }

    private func parseOllamaResponse(_ data: Data) throws -> AILLMResponse {
        do {
            let response = try decoder.decode(OllamaResponse.self, from: data)
            return try makeResponse(
                content: response.message?.content,
                promptTokens: response.promptEvalCount,
                completionTokens: response.evalCount
            )
        } catch let error as LLMClientError {
            throw error
        } catch {
            throw LLMClientError.invalidResponse(String(describing: error))
        }
    }

    private func makeResponse(content: String?, promptTokens: Int?, completionTokens: Int?) throws -> AILLMResponse {
        guard let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMClientError.invalidResponse("Missing assistant content.")
        }
        return AILLMResponse(content: content, promptTokens: promptTokens, completionTokens: completionTokens)
    }

    private func apiKeyIfConfigured(_ ref: String?) async throws -> String? {
        guard let ref else {
            return nil
        }
        guard let apiKey = try await apiKeyStore.apiKey(ref: ref), !apiKey.isEmpty else {
            throw LLMClientError.missingAPIKey(ref)
        }
        return apiKey
    }

    private func defaultHeaders() -> [String: String] {
        ["Content-Type": "application/json"]
    }

    private func endpoint(baseURL: String, path: [String]) throws -> URL {
        guard var url = URL(string: baseURL),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil else {
            throw LLMClientError.invalidBaseURL(baseURL)
        }

        for component in path {
            url.appendPathComponent(component)
        }
        return url
    }
}

private struct LLMMessageDTO: Codable, Equatable {
    let role: String
    let content: String

    init(_ message: AILLMMessage) {
        self.role = message.role.rawValue
        self.content = message.content
    }
}

private struct OpenAIRequest: Codable, Equatable {
    let model: String
    let messages: [LLMMessageDTO]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct OpenAIResponse: Codable, Equatable {
    let choices: [Choice]?
    let usage: Usage?

    struct Choice: Codable, Equatable {
        let message: Message
    }

    struct Message: Codable, Equatable {
        let content: String?
    }

    struct Usage: Codable, Equatable {
        let promptTokens: Int?
        let completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }
}

private struct AnthropicRequest: Codable, Equatable {
    let model: String
    let maxTokens: Int
    let temperature: Double
    let system: String?
    let messages: [LLMMessageDTO]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case temperature
        case system
        case messages
    }
}

private struct AnthropicResponse: Codable, Equatable {
    let content: [ContentBlock]?
    let usage: Usage?

    struct ContentBlock: Codable, Equatable {
        let type: String
        let text: String
    }

    struct Usage: Codable, Equatable {
        let inputTokens: Int?
        let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }
}

private struct OllamaRequest: Codable, Equatable {
    let model: String
    let messages: [LLMMessageDTO]
    let stream: Bool
    let options: OllamaOptions
}

private struct OllamaOptions: Codable, Equatable {
    let temperature: Double
    let numPredict: Int

    enum CodingKeys: String, CodingKey {
        case temperature
        case numPredict = "num_predict"
    }
}

private struct OllamaResponse: Codable, Equatable {
    let message: LLMMessageDTO?
    let promptEvalCount: Int?
    let evalCount: Int?

    enum CodingKeys: String, CodingKey {
        case message
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
    }
}
