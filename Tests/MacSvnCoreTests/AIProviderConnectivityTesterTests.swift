import Foundation
import XCTest
@testable import MacSvnCore

final class AIProviderConnectivityTesterTests: XCTestCase {
    func testConnectionTesterSendsPingAndMapsUsage() async throws {
        let provider = AIProvider(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            name: "Ollama",
            kind: .ollama,
            baseURL: "http://localhost:11434",
            model: "qwen",
            apiKeyRef: nil,
            maxTokens: 128,
            temperature: 0
        )
        let llm = FakePingLLM(response: AILLMResponse(content: "pong", promptTokens: 2, completionTokens: 1))
        let tester = AIProviderConnectivityTester(llmClient: llm, latencyMeasurer: { operation in
            (try await operation(), 42)
        })

        let result = try await tester.testConnection(provider: provider)

        let call = await llm.onlyCall()
        XCTAssertEqual(call.provider, provider)
        XCTAssertEqual(call.messages.last?.role, .user)
        XCTAssertTrue(call.messages.last?.content.contains("ping") == true)
        XCTAssertEqual(result, AIProviderConnectionTestResult(
            providerID: provider.id,
            latencyMilliseconds: 42,
            promptTokens: 2,
            completionTokens: 1
        ))
    }

    func testConnectionTesterRejectsEmptyPongAndMapsFailure() async {
        let provider = AIProvider(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
            name: "Broken",
            kind: .openAICompatible,
            baseURL: "https://api.example.com/v1",
            model: "gpt",
            apiKeyRef: "key",
            maxTokens: 128,
            temperature: 0
        )
        let tester = AIProviderConnectivityTester(
            llmClient: FakePingLLM(response: AILLMResponse(content: "   ", promptTokens: nil, completionTokens: nil)),
            latencyMeasurer: { operation in
                (try await operation(), 1)
            }
        )

        do {
            _ = try await tester.testConnection(provider: provider)
            XCTFail("Expected ping failure")
        } catch let error as AIProviderConnectivityError {
            XCTAssertEqual(error, .pingFailed("Empty ping response."))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private actor FakePingLLM: LLMChatting {
    struct Call: Equatable {
        let provider: AIProvider
        let messages: [AILLMMessage]
    }

    private let response: AILLMResponse
    private var calls: [Call] = []

    init(response: AILLMResponse) {
        self.response = response
    }

    func chat(provider: AIProvider, messages: [AILLMMessage]) async throws -> AILLMResponse {
        calls.append(Call(provider: provider, messages: messages))
        return response
    }

    func onlyCall() -> Call {
        calls[0]
    }
}
