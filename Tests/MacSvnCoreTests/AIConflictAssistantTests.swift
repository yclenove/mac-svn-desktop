import Foundation
import XCTest
@testable import MacSvnCore

final class AIConflictAssistantTests: XCTestCase {
    func testSuggestResolutionParsesJSONRedactsSecretsAndRecordsMetadata() async throws {
        let provider = AIProvider(
            name: "DeepSeek",
            kind: .openAICompatible,
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-chat",
            apiKeyRef: "keychain://deepseek",
            maxTokens: 32_000,
            temperature: 0.2
        )
        let llm = FakeConflictLLMClient(responses: [
            AILLMResponse(
                content: """
                {
                  "mergedText": "let token = credentialStore.token\\ntry auth.login()",
                  "rationale": "保留安全 token 读取并保留登录调用。",
                  "confidence": "high"
                }
                """,
                promptTokens: 140,
                completionTokens: 42
            )
        ])
        let assistant = AIConflictAssistant(
            providerManager: FakeConflictProviderManager(providers: [provider]),
            llmClient: llm
        )
        let context = AIConflictAssistContext(
            path: "Sources/Login.swift",
            conflictIndex: 2,
            baseLines: ["let token = \"sk-1234567890abcdef\""],
            mineLines: ["let token = credentialStore.token"],
            theirsLines: ["let token = \"sk-1234567890abcdef\"", "try auth.login()"],
            leadingContext: ["func login() {"],
            trailingContext: ["}"]
        )

        let suggestion = try await assistant.suggestResolution(
            context: context,
            privacySettings: AIPrivacySettings()
        )
        let calls = await llm.recordedCalls()
        let prompt = calls[0].messages.map(\.content).joined(separator: "\n")

        XCTAssertEqual(suggestion.providerID, provider.id)
        XCTAssertEqual(suggestion.mergedLines, [
            "let token = credentialStore.token",
            "try auth.login()"
        ])
        XCTAssertEqual(suggestion.rationale, "保留安全 token 读取并保留登录调用。")
        XCTAssertEqual(suggestion.confidence, .high)
        XCTAssertEqual(suggestion.redactionMatches.map(\.ruleID), ["openai-api-key"])
        XCTAssertEqual(suggestion.promptCount, 1)
        XCTAssertTrue(prompt.contains("***REDACTED***"))
        XCTAssertFalse(prompt.contains("sk-1234567890abcdef"))
        XCTAssertTrue(prompt.contains("只输出 JSON"))
        XCTAssertTrue(prompt.contains("Sources/Login.swift"))
    }

    func testThrowsForMissingProviderEmptyContextEmptyResponseAndInvalidJSON() async throws {
        let provider = AIProvider(
            name: "Local",
            kind: .ollama,
            baseURL: "http://localhost:11434",
            model: "llama3",
            apiKeyRef: nil,
            maxTokens: 4096,
            temperature: 0.1
        )

        try await assertSuggestThrows(
            providerManager: FakeConflictProviderManager(providers: []),
            llmClient: FakeConflictLLMClient(responses: []),
            context: validContext(),
            expected: .missingDefaultProvider
        )
        try await assertSuggestThrows(
            providerManager: FakeConflictProviderManager(providers: [provider]),
            llmClient: FakeConflictLLMClient(responses: []),
            context: AIConflictAssistContext(
                path: "a.swift",
                conflictIndex: 0,
                baseLines: [],
                mineLines: [],
                theirsLines: [],
                leadingContext: [],
                trailingContext: []
            ),
            expected: .emptyConflict
        )
        try await assertSuggestThrows(
            providerManager: FakeConflictProviderManager(providers: [provider]),
            llmClient: FakeConflictLLMClient(responses: [
                AILLMResponse(content: "   ", promptTokens: nil, completionTokens: nil)
            ]),
            context: validContext(),
            expected: .emptyModelResponse
        )
        try await assertSuggestThrows(
            providerManager: FakeConflictProviderManager(providers: [provider]),
            llmClient: FakeConflictLLMClient(responses: [
                AILLMResponse(content: "not json", promptTokens: nil, completionTokens: nil)
            ]),
            context: validContext(),
            expected: .invalidModelResponse("not json")
        )
    }

    private func assertSuggestThrows(
        providerManager: FakeConflictProviderManager,
        llmClient: FakeConflictLLMClient,
        context: AIConflictAssistContext,
        expected: AIConflictAssistError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let assistant = AIConflictAssistant(providerManager: providerManager, llmClient: llmClient)

        do {
            _ = try await assistant.suggestResolution(
                context: context,
                privacySettings: AIPrivacySettings()
            )
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as AIConflictAssistError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected AIConflictAssistError, got \(error)", file: file, line: line)
        }
    }

    func testSuggestResolutionsParsesBlockSuggestionsAndRedactsAllContexts() async throws {
        let provider = AIProvider(
            name: "DeepSeek",
            kind: .openAICompatible,
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-chat",
            apiKeyRef: "keychain://deepseek",
            maxTokens: 32_000,
            temperature: 0.2
        )
        let llm = FakeConflictLLMClient(responses: [
            AILLMResponse(
                content: """
                {
                  "suggestions": [
                    {
                      "conflictIndex": 0,
                      "mergedText": "first merged",
                      "rationale": "第一块可自动合并。",
                      "confidence": "high"
                    },
                    {
                      "conflictIndex": 1,
                      "mergedText": "second merged",
                      "rationale": "第二块风险高，需要人工确认。",
                      "confidence": "low"
                    }
                  ]
                }
                """,
                promptTokens: 240,
                completionTokens: 80
            )
        ])
        let assistant = AIConflictAssistant(
            providerManager: FakeConflictProviderManager(providers: [provider]),
            llmClient: llm
        )
        let contexts = [
            AIConflictAssistContext(
                path: "Sources/Login.swift",
                conflictIndex: 0,
                baseLines: ["let token = \"sk-1234567890abcdef\""],
                mineLines: ["let token = credentialStore.token"],
                theirsLines: ["let token = \"sk-1234567890abcdef\"", "try auth.login()"],
                leadingContext: [],
                trailingContext: []
            ),
            AIConflictAssistContext(
                path: "Sources/Login.swift",
                conflictIndex: 1,
                baseLines: ["return false"],
                mineLines: ["return isValid"],
                theirsLines: ["return hasPermission"],
                leadingContext: [],
                trailingContext: []
            )
        ]

        let preview = try await assistant.suggestResolutions(
            contexts: contexts,
            privacySettings: AIPrivacySettings()
        )
        let calls = await llm.recordedCalls()
        let prompt = calls[0].messages.map(\.content).joined(separator: "\n")

        XCTAssertEqual(preview.providerID, provider.id)
        XCTAssertEqual(preview.promptCount, 1)
        XCTAssertEqual(preview.redactionMatches.map(\.ruleID), ["openai-api-key"])
        XCTAssertEqual(preview.suggestions.map(\.conflictIndex), [0, 1])
        XCTAssertEqual(preview.suggestions.map(\.mergedLines), [["first merged"], ["second merged"]])
        XCTAssertEqual(preview.suggestions.map(\.confidence), [.high, .low])
        XCTAssertTrue(prompt.contains("***REDACTED***"))
        XCTAssertFalse(prompt.contains("sk-1234567890abcdef"))
        XCTAssertTrue(prompt.contains("suggestions"))
    }

    func testSuggestResolutionsRejectsEmptyContextList() async throws {
        let provider = AIProvider(
            name: "Local",
            kind: .ollama,
            baseURL: "http://localhost:11434",
            model: "llama3",
            apiKeyRef: nil,
            maxTokens: 4096,
            temperature: 0.1
        )
        let assistant = AIConflictAssistant(
            providerManager: FakeConflictProviderManager(providers: [provider]),
            llmClient: FakeConflictLLMClient(responses: [])
        )

        do {
            _ = try await assistant.suggestResolutions(
                contexts: [],
                privacySettings: AIPrivacySettings()
            )
            XCTFail("Expected emptyConflict")
        } catch let error as AIConflictAssistError {
            XCTAssertEqual(error, .emptyConflict)
        } catch {
            XCTFail("Expected AIConflictAssistError, got \(error)")
        }
    }
}

private func validContext() -> AIConflictAssistContext {
    AIConflictAssistContext(
        path: "a.swift",
        conflictIndex: 0,
        baseLines: ["base"],
        mineLines: ["mine"],
        theirsLines: ["theirs"],
        leadingContext: ["before"],
        trailingContext: ["after"]
    )
}

private struct ConflictLLMCall: Equatable, Sendable {
    let provider: AIProvider
    let messages: [AILLMMessage]
}

private actor FakeConflictLLMClient: LLMChatting {
    private var responses: [AILLMResponse]
    private var calls: [ConflictLLMCall] = []

    init(responses: [AILLMResponse]) {
        self.responses = responses
    }

    func recordedCalls() -> [ConflictLLMCall] {
        calls
    }

    func chat(provider: AIProvider, messages: [AILLMMessage]) async throws -> AILLMResponse {
        calls.append(ConflictLLMCall(provider: provider, messages: messages))
        guard !responses.isEmpty else {
            return AILLMResponse(content: "", promptTokens: nil, completionTokens: nil)
        }
        return responses.removeFirst()
    }
}

private actor FakeConflictProviderManager: AIProviderManaging {
    private let providers: [AIProvider]
    private let defaultID: UUID?

    init(providers: [AIProvider]) {
        self.providers = providers
        self.defaultID = providers.first?.id
    }

    func loadProviders() async throws -> [AIProvider] {
        providers
    }

    func saveProvider(_ provider: AIProvider, makeDefault: Bool) async throws -> AIProvider {
        provider
    }

    func deleteProvider(id: UUID) async throws {}

    func setDefaultProvider(id: UUID) async throws -> AIProvider {
        guard let provider = providers.first(where: { $0.id == id }) else {
            throw AIProviderError.providerNotFound(id)
        }
        return provider
    }

    func defaultProviderID() async -> UUID? {
        defaultID
    }
}
