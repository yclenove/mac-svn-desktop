import Foundation

public struct AIProviderConnectivityTester: AIProviderConnectivityTesting, Sendable {
    public typealias LatencyMeasurer = @Sendable (
        @Sendable () async throws -> AILLMResponse
    ) async throws -> (AILLMResponse, Int)

    private let llmClient: any LLMChatting
    private let latencyMeasurer: LatencyMeasurer

    public init(
        llmClient: any LLMChatting = LLMHTTPClient(),
        latencyMeasurer: @escaping LatencyMeasurer = AIProviderConnectivityTester.defaultLatencyMeasurer
    ) {
        self.llmClient = llmClient
        self.latencyMeasurer = latencyMeasurer
    }

    public func testConnection(provider: AIProvider) async throws -> AIProviderConnectionTestResult {
        let messages = [
            AILLMMessage(role: .system, content: "You are a connection test endpoint. Reply with pong only."),
            AILLMMessage(role: .user, content: "ping")
        ]
        let (response, latencyMilliseconds) = try await latencyMeasurer {
            try await llmClient.chat(provider: provider, messages: messages)
        }

        guard !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderConnectivityError.pingFailed("Empty ping response.")
        }

        return AIProviderConnectionTestResult(
            providerID: provider.id,
            latencyMilliseconds: latencyMilliseconds,
            promptTokens: response.promptTokens ?? 0,
            completionTokens: response.completionTokens ?? 0
        )
    }

    public static func defaultLatencyMeasurer(
        operation: @Sendable () async throws -> AILLMResponse
    ) async throws -> (AILLMResponse, Int) {
        let start = Date()
        let response = try await operation()
        let milliseconds = max(0, Int(Date().timeIntervalSince(start) * 1_000))
        return (response, milliseconds)
    }
}
