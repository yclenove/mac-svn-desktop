import Foundation
import XCTest
@testable import MacSvnCore

final class LLMHTTPClientTests: XCTestCase {
    func testOpenAICompatibleRequestUsesChatCompletionsAndBearerToken() async throws {
        let provider = makeProvider(kind: .openAICompatible, baseURL: "https://api.example.com/v1", apiKeyRef: "key-ref")
        let transport = FakeAIHTTPTransport(response: AIHTTPResponse(
            statusCode: 200,
            data: Data("""
            {"choices":[{"message":{"content":"提交说明"}}],"usage":{"prompt_tokens":12,"completion_tokens":3}}
            """.utf8)
        ))
        let client = LLMHTTPClient(transport: transport, apiKeyStore: FakeAPIKeyStore(keys: ["key-ref": "sk-test"]))

        let response = try await client.chat(provider: provider, messages: [.init(role: .user, content: "ping")])

        let request = try await transport.onlyRequest()
        XCTAssertEqual(request.url.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(request.headers["Authorization"], "Bearer sk-test")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertTrue(String(decoding: request.body, as: UTF8.self).contains("\"model\":\"gpt-test\""))
        XCTAssertEqual(response, AILLMResponse(content: "提交说明", promptTokens: 12, completionTokens: 3))
    }

    func testAnthropicRequestUsesMessagesEndpointAndAPIKeyHeader() async throws {
        let provider = makeProvider(kind: .anthropic, baseURL: "https://api.anthropic.com", apiKeyRef: "anthropic-ref")
        let transport = FakeAIHTTPTransport(response: AIHTTPResponse(
            statusCode: 200,
            data: Data("""
            {"content":[{"type":"text","text":"评审结果"}],"usage":{"input_tokens":8,"output_tokens":5}}
            """.utf8)
        ))
        let client = LLMHTTPClient(transport: transport, apiKeyStore: FakeAPIKeyStore(keys: ["anthropic-ref": "sk-ant"]))

        let response = try await client.chat(provider: provider, messages: [
            .init(role: .system, content: "system prompt"),
            .init(role: .user, content: "user prompt")
        ])

        let request = try await transport.onlyRequest()
        XCTAssertEqual(request.url.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.headers["x-api-key"], "sk-ant")
        XCTAssertEqual(request.headers["anthropic-version"], "2023-06-01")
        XCTAssertTrue(String(decoding: request.body, as: UTF8.self).contains("\"system\":\"system prompt\""))
        XCTAssertEqual(response, AILLMResponse(content: "评审结果", promptTokens: 8, completionTokens: 5))
    }

    func testOllamaRequestDoesNotRequireAPIKeyAndParsesCounts() async throws {
        let provider = makeProvider(kind: .ollama, baseURL: "http://localhost:11434", apiKeyRef: nil)
        let transport = FakeAIHTTPTransport(response: AIHTTPResponse(
            statusCode: 200,
            data: Data("""
            {"message":{"role":"assistant","content":"本地结果"},"prompt_eval_count":4,"eval_count":7}
            """.utf8)
        ))
        let client = LLMHTTPClient(transport: transport, apiKeyStore: FakeAPIKeyStore(keys: [:]))

        let response = try await client.chat(provider: provider, messages: [.init(role: .user, content: "ping")])

        let request = try await transport.onlyRequest()
        XCTAssertEqual(request.url.absoluteString, "http://localhost:11434/api/chat")
        XCTAssertNil(request.headers["Authorization"])
        XCTAssertTrue(String(decoding: request.body, as: UTF8.self).contains("\"stream\":false"))
        XCTAssertEqual(response, AILLMResponse(content: "本地结果", promptTokens: 4, completionTokens: 7))
    }

    func testThrowsForMissingKeyBadURLHTTPErrorAndInvalidResponse() async throws {
        let keyedProvider = makeProvider(kind: .openAICompatible, baseURL: "https://api.example.com/v1", apiKeyRef: "missing")
        let missingKeyClient = LLMHTTPClient(
            transport: FakeAIHTTPTransport(response: AIHTTPResponse(statusCode: 200, data: Data())),
            apiKeyStore: FakeAPIKeyStore(keys: [:])
        )
        await XCTAssertThrowsAsyncError({
            try await missingKeyClient.chat(provider: keyedProvider, messages: [])
        }) { error in
            XCTAssertEqual(error as? LLMClientError, .missingAPIKey("missing"))
        }

        let badURLProvider = makeProvider(kind: .ollama, baseURL: "not a url", apiKeyRef: nil)
        await XCTAssertThrowsAsyncError({
            try await missingKeyClient.chat(provider: badURLProvider, messages: [])
        }) { error in
            XCTAssertEqual(error as? LLMClientError, .invalidBaseURL("not a url"))
        }

        let availableKeyProvider = makeProvider(kind: .openAICompatible, baseURL: "https://api.example.com/v1", apiKeyRef: "key-ref")
        let httpClient = LLMHTTPClient(
            transport: FakeAIHTTPTransport(response: AIHTTPResponse(statusCode: 429, data: Data("rate limited".utf8))),
            apiKeyStore: FakeAPIKeyStore(keys: ["key-ref": "sk-test"])
        )
        await XCTAssertThrowsAsyncError({
            try await httpClient.chat(provider: availableKeyProvider, messages: [])
        }) { error in
            XCTAssertEqual(error as? LLMClientError, .httpError(statusCode: 429, body: "rate limited"))
        }

        let invalidClient = LLMHTTPClient(
            transport: FakeAIHTTPTransport(response: AIHTTPResponse(statusCode: 200, data: Data("{}".utf8))),
            apiKeyStore: FakeAPIKeyStore(keys: ["key-ref": "sk-test"])
        )
        await XCTAssertThrowsAsyncError({
            try await invalidClient.chat(provider: availableKeyProvider, messages: [])
        }) { error in
            XCTAssertEqual(error as? LLMClientError, .invalidResponse("Missing assistant content."))
        }
    }

    private func makeProvider(kind: AIProviderKind, baseURL: String, apiKeyRef: String?) -> AIProvider {
        AIProvider(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            name: "Provider",
            kind: kind,
            baseURL: baseURL,
            model: "gpt-test",
            apiKeyRef: apiKeyRef,
            maxTokens: 512,
            temperature: 0.2
        )
    }
}

private actor FakeAIHTTPTransport: AIHTTPTransport {
    private let response: AIHTTPResponse
    private var requests: [AIHTTPRequest] = []

    init(response: AIHTTPResponse) {
        self.response = response
    }

    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        requests.append(request)
        return response
    }

    func onlyRequest() throws -> AIHTTPRequest {
        guard requests.count == 1, let request = requests.first else {
            throw LLMClientError.invalidResponse("Expected exactly one request.")
        }
        return request
    }
}

private actor FakeAPIKeyStore: AIAPIKeyStoring {
    let keys: [String: String]

    init(keys: [String: String]) {
        self.keys = keys
    }

    func saveAPIKey(_ apiKey: String, for providerID: UUID) async throws -> String {
        "unused"
    }

    func apiKey(ref: String) async throws -> String? {
        keys[ref]
    }

    func deleteAPIKey(ref: String) async throws {}
}

private func XCTAssertThrowsAsyncError<T>(
    _ expression: @escaping () async throws -> T,
    _ handler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        handler(error)
    }
}
