import Foundation
import XCTest
@testable import MacSvnCore

final class AIPreCommitReviewerTests: XCTestCase {
    func testReviewParsesFindingsRedactsSecretsAndAddsSecretWarning() async throws {
        let provider = AIProvider(
            name: "DeepSeek",
            kind: .openAICompatible,
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-chat",
            apiKeyRef: "keychain://deepseek",
            maxTokens: 32_000,
            temperature: 0.2
        )
        let diffProvider = FakeReviewDiffProvider(diffs: [
            "Sources/Login.swift": """
            Index: Sources/Login.swift
            @@ -1,2 +1,2 @@
            -let token = "sk-1234567890abcdef"
            +let token = credentialStore.token
            +try! auth.login()
            """
        ])
        let llm = FakeReviewLLMClient(responses: [
            AILLMResponse(
                content: """
                {
                  "summary": "发现 2 条建议",
                  "findings": [
                    {
                      "severity": "blockingSuggestion",
                      "category": "correctness",
                      "path": "Sources/Login.swift",
                      "line": 3,
                      "message": "避免在登录流程中使用 try!",
                      "rationale": "认证失败会导致崩溃。"
                    },
                    {
                      "severity": "tip",
                      "category": "testing",
                      "path": "Sources/Login.swift",
                      "line": null,
                      "message": "补充失败路径测试。",
                      "rationale": null
                    }
                  ]
                }
                """,
                promptTokens: 160,
                completionTokens: 80
            )
        ])
        let reviewer = AIPreCommitReviewer(
            providerManager: FakeReviewProviderManager(providers: [provider]),
            diffProvider: diffProvider,
            llmClient: llm
        )

        let result = try await reviewer.review(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            paths: ["Sources/Login.swift"],
            privacySettings: AIPrivacySettings()
        )
        let llmCalls = await llm.recordedCalls()
        let diffCalls = await diffProvider.recordedCalls()

        XCTAssertEqual(result.providerID, provider.id)
        XCTAssertEqual(result.summary, "发现 2 条建议")
        XCTAssertEqual(result.sourceFileCount, 1)
        XCTAssertFalse(result.usedMapReduce)
        XCTAssertEqual(result.promptCount, 1)
        XCTAssertTrue(result.hasSuspectedSecretWarning)
        XCTAssertEqual(result.redactionMatches.map(\.ruleID), ["openai-api-key"])
        XCTAssertEqual(result.findings.map(\.severity), [.blockingSuggestion, .tip, .blockingSuggestion])
        XCTAssertEqual(result.findings.last?.category, .suspectedSecret)
        XCTAssertEqual(diffCalls.map(\.target), ["Sources/Login.swift"])
        XCTAssertTrue(llmCalls[0].messages.map(\.content).joined().contains("***REDACTED***"))
        XCTAssertFalse(llmCalls[0].messages.map(\.content).joined().contains("sk-1234567890abcdef"))
        XCTAssertTrue(llmCalls[0].messages.map(\.content).joined().contains("只输出 JSON"))
    }

    func testLongDiffsAreSummarizedBeforeFinalReview() async throws {
        let provider = AIProvider(
            name: "Local",
            kind: .ollama,
            baseURL: "http://localhost:11434",
            model: "llama3",
            apiKeyRef: nil,
            maxTokens: 4096,
            temperature: 0.1
        )
        let longLine = String(repeating: "+changed\n", count: 40)
        let diffProvider = FakeReviewDiffProvider(diffs: [
            "A.swift": "Index: A.swift\n\(longLine)",
            "B.swift": "Index: B.swift\n\(longLine)"
        ])
        let llm = FakeReviewLLMClient(responses: [
            AILLMResponse(content: "A.swift: 登录流程变化", promptTokens: 30, completionTokens: 8),
            AILLMResponse(content: "B.swift: 测试覆盖变化", promptTokens: 30, completionTokens: 8),
            AILLMResponse(
                content: """
                {
                  "summary": "长 diff 评审完成",
                  "findings": [
                    {
                      "severity": "generalSuggestion",
                      "category": "maintainability",
                      "path": "A.swift",
                      "line": null,
                      "message": "拆分登录流程改动。",
                      "rationale": "便于审查。"
                    }
                  ]
                }
                """,
                promptTokens: 60,
                completionTokens: 20
            )
        ])
        let reviewer = AIPreCommitReviewer(
            providerManager: FakeReviewProviderManager(providers: [provider]),
            diffProvider: diffProvider,
            llmClient: llm,
            maxPromptCharacters: 120
        )

        let result = try await reviewer.review(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            paths: ["A.swift", "B.swift"],
            privacySettings: AIPrivacySettings()
        )
        let calls = await llm.recordedCalls()

        XCTAssertEqual(result.summary, "长 diff 评审完成")
        XCTAssertTrue(result.usedMapReduce)
        XCTAssertEqual(result.promptCount, 3)
        XCTAssertTrue(calls[0].messages.map(\.content).joined().contains("请摘要这个文件 diff"))
        XCTAssertTrue(calls[2].messages.map(\.content).joined().contains("A.swift: 登录流程变化"))
        XCTAssertTrue(calls[2].messages.map(\.content).joined().contains("B.swift: 测试覆盖变化"))
    }

    func testThrowsForMissingInputsAndInvalidModelResponse() async throws {
        let provider = AIProvider(
            name: "Claude",
            kind: .anthropic,
            baseURL: "https://api.anthropic.com",
            model: "claude",
            apiKeyRef: "keychain://claude",
            maxTokens: 4096,
            temperature: 0.2
        )

        try await assertReviewThrows(
            providerManager: FakeReviewProviderManager(providers: []),
            diffProvider: FakeReviewDiffProvider(diffs: ["a.swift": "+a"]),
            llmClient: FakeReviewLLMClient(responses: []),
            paths: ["a.swift"],
            expected: .missingDefaultProvider
        )
        try await assertReviewThrows(
            providerManager: FakeReviewProviderManager(providers: [provider]),
            diffProvider: FakeReviewDiffProvider(diffs: ["a.swift": "+a"]),
            llmClient: FakeReviewLLMClient(responses: []),
            paths: [],
            expected: .emptySelection
        )
        try await assertReviewThrows(
            providerManager: FakeReviewProviderManager(providers: [provider]),
            diffProvider: FakeReviewDiffProvider(diffs: ["a.swift": "   "]),
            llmClient: FakeReviewLLMClient(responses: []),
            paths: ["a.swift"],
            expected: .emptyDiff
        )
        try await assertReviewThrows(
            providerManager: FakeReviewProviderManager(providers: [provider]),
            diffProvider: FakeReviewDiffProvider(diffs: ["a.swift": "+a"]),
            llmClient: FakeReviewLLMClient(responses: [
                AILLMResponse(content: "not json", promptTokens: nil, completionTokens: nil)
            ]),
            paths: ["a.swift"],
            expected: .invalidModelResponse("not json")
        )
    }

    private func assertReviewThrows(
        providerManager: FakeReviewProviderManager,
        diffProvider: FakeReviewDiffProvider,
        llmClient: FakeReviewLLMClient,
        paths: [String],
        expected: AIPreCommitReviewError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let reviewer = AIPreCommitReviewer(
            providerManager: providerManager,
            diffProvider: diffProvider,
            llmClient: llmClient
        )

        do {
            _ = try await reviewer.review(
                wc: URL(fileURLWithPath: "/tmp/wc"),
                paths: paths,
                privacySettings: AIPrivacySettings()
            )
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as AIPreCommitReviewError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected AIPreCommitReviewError, got \(error)", file: file, line: line)
        }
    }
}

private struct ReviewLLMCall: Equatable, Sendable {
    let provider: AIProvider
    let messages: [AILLMMessage]
}

private struct ReviewDiffCall: Equatable, Sendable {
    let wc: URL
    let target: String
    let r1: Revision?
    let r2: Revision?
}

private actor FakeReviewLLMClient: LLMChatting {
    private var responses: [AILLMResponse]
    private var calls: [ReviewLLMCall] = []

    init(responses: [AILLMResponse]) {
        self.responses = responses
    }

    func recordedCalls() -> [ReviewLLMCall] {
        calls
    }

    func chat(provider: AIProvider, messages: [AILLMMessage]) async throws -> AILLMResponse {
        calls.append(ReviewLLMCall(provider: provider, messages: messages))
        guard !responses.isEmpty else {
            return AILLMResponse(content: "", promptTokens: nil, completionTokens: nil)
        }
        return responses.removeFirst()
    }
}

private actor FakeReviewDiffProvider: DiffProviding {
    private let diffs: [String: String]
    private var calls: [ReviewDiffCall] = []

    init(diffs: [String: String]) {
        self.diffs = diffs
    }

    func recordedCalls() -> [ReviewDiffCall] {
        calls
    }

    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        calls.append(ReviewDiffCall(wc: wc, target: target, r1: r1, r2: r2))
        return diffs[target] ?? ""
    }
}

private actor FakeReviewProviderManager: AIProviderManaging {
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
