import Foundation
import XCTest
@testable import MacSvnCore

final class AICommitMessageGeneratorTests: XCTestCase {
    func testGenerateUsesDefaultProviderSelectedDiffsAndRedactsSecrets() async throws {
        let provider = AIProvider(
            name: "DeepSeek",
            kind: .openAICompatible,
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-chat",
            apiKeyRef: "keychain://deepseek",
            maxTokens: 32_000,
            temperature: 0.2
        )
        let providerManager = FakeAIProviderManager(providers: [provider])
        let diffProvider = FakeCommitDiffProvider(diffs: [
            "Sources/Login.swift": """
            Index: Sources/Login.swift
            @@ -1,1 +1,1 @@
            -let token = "sk-1234567890abcdef"
            +let token = credentialStore.token
            """,
            "Tests/LoginTests.swift": """
            Index: Tests/LoginTests.swift
            @@ -1,1 +1,1 @@
            +func testCredentialStoreToken() {}
            """
        ])
        let llm = FakeLLMClient(responses: [
            AILLMResponse(content: "fix: 修复登录令牌读取", promptTokens: 120, completionTokens: 9)
        ])
        let generator = AICommitMessageGenerator(
            providerManager: providerManager,
            diffProvider: diffProvider,
            llmClient: llm
        )

        let draft = try await generator.generateCommitMessage(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            paths: ["Sources/Login.swift", "Tests/LoginTests.swift"],
            format: .conventionalChinese,
            privacySettings: AIPrivacySettings()
        )
        let calls = await llm.recordedCalls()
        let diffCalls = await diffProvider.recordedCalls()

        XCTAssertEqual(draft.message, "fix: 修复登录令牌读取")
        XCTAssertEqual(draft.providerID, provider.id)
        XCTAssertEqual(draft.sourceFileCount, 2)
        XCTAssertFalse(draft.usedMapReduce)
        XCTAssertEqual(draft.redactionMatches.map(\.ruleID), ["openai-api-key"])
        XCTAssertEqual(diffCalls.map(\.target), ["Sources/Login.swift", "Tests/LoginTests.swift"])
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].provider, provider)
        XCTAssertTrue(calls[0].messages.map(\.content).joined().contains("Conventional Commits 中文式"))
        XCTAssertTrue(calls[0].messages.map(\.content).joined().contains("***REDACTED***"))
        XCTAssertFalse(calls[0].messages.map(\.content).joined().contains("sk-1234567890abcdef"))
    }

    func testLongDiffsAreSummarizedPerFileBeforeFinalMessage() async throws {
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
        let diffProvider = FakeCommitDiffProvider(diffs: [
            "A.swift": "Index: A.swift\n\(longLine)",
            "B.swift": "Index: B.swift\n\(longLine)"
        ])
        let llm = FakeLLMClient(responses: [
            AILLMResponse(content: "A.swift: 调整登录流程", promptTokens: 30, completionTokens: 8),
            AILLMResponse(content: "B.swift: 补充测试覆盖", promptTokens: 30, completionTokens: 8),
            AILLMResponse(content: "完善登录流程并补充测试", promptTokens: 40, completionTokens: 10)
        ])
        let generator = AICommitMessageGenerator(
            providerManager: FakeAIProviderManager(providers: [provider]),
            diffProvider: diffProvider,
            llmClient: llm,
            maxPromptCharacters: 120
        )

        let draft = try await generator.generateCommitMessage(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            paths: ["A.swift", "B.swift"],
            format: .oneLineChinese,
            privacySettings: AIPrivacySettings()
        )
        let calls = await llm.recordedCalls()

        XCTAssertEqual(draft.message, "完善登录流程并补充测试")
        XCTAssertTrue(draft.usedMapReduce)
        XCTAssertEqual(draft.promptCount, 3)
        XCTAssertTrue(calls[0].messages.map(\.content).joined().contains("请摘要这个文件 diff"))
        XCTAssertTrue(calls[2].messages.map(\.content).joined().contains("A.swift: 调整登录流程"))
        XCTAssertTrue(calls[2].messages.map(\.content).joined().contains("B.swift: 补充测试覆盖"))
    }

    func testThrowsWhenNoDefaultProviderOrSelectionOrDiffContent() async throws {
        let provider = AIProvider(
            name: "Claude",
            kind: .anthropic,
            baseURL: "https://api.anthropic.com",
            model: "claude",
            apiKeyRef: "keychain://claude",
            maxTokens: 4096,
            temperature: 0.2
        )

        try await assertGenerateThrows(
            providerManager: FakeAIProviderManager(providers: []),
            diffProvider: FakeCommitDiffProvider(diffs: ["a.swift": "+a"]),
            paths: ["a.swift"],
            expected: .missingDefaultProvider
        )
        try await assertGenerateThrows(
            providerManager: FakeAIProviderManager(providers: [provider]),
            diffProvider: FakeCommitDiffProvider(diffs: ["a.swift": "+a"]),
            paths: [],
            expected: .emptySelection
        )
        try await assertGenerateThrows(
            providerManager: FakeAIProviderManager(providers: [provider]),
            diffProvider: FakeCommitDiffProvider(diffs: ["a.swift": "   "]),
            paths: ["a.swift"],
            expected: .emptyDiff
        )
    }

    private func assertGenerateThrows(
        providerManager: FakeAIProviderManager,
        diffProvider: FakeCommitDiffProvider,
        paths: [String],
        expected: AICommitMessageError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let generator = AICommitMessageGenerator(
            providerManager: providerManager,
            diffProvider: diffProvider,
            llmClient: FakeLLMClient(responses: [])
        )

        do {
            _ = try await generator.generateCommitMessage(
                wc: URL(fileURLWithPath: "/tmp/wc"),
                paths: paths,
                format: .oneLineChinese,
                privacySettings: AIPrivacySettings()
            )
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as AICommitMessageError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected AICommitMessageError, got \(error)", file: file, line: line)
        }
    }
}

private struct LLMCall: Equatable, Sendable {
    let provider: AIProvider
    let messages: [AILLMMessage]
}

private struct CommitDiffCall: Equatable, Sendable {
    let wc: URL
    let target: String
    let r1: Revision?
    let r2: Revision?
}

private actor FakeLLMClient: LLMChatting {
    private var responses: [AILLMResponse]
    private var calls: [LLMCall] = []

    init(responses: [AILLMResponse]) {
        self.responses = responses
    }

    func recordedCalls() -> [LLMCall] {
        calls
    }

    func chat(provider: AIProvider, messages: [AILLMMessage]) async throws -> AILLMResponse {
        calls.append(LLMCall(provider: provider, messages: messages))
        guard !responses.isEmpty else {
            return AILLMResponse(content: "", promptTokens: nil, completionTokens: nil)
        }
        return responses.removeFirst()
    }
}

private actor FakeCommitDiffProvider: DiffProviding {
    private let diffs: [String: String]
    private var calls: [CommitDiffCall] = []

    init(diffs: [String: String]) {
        self.diffs = diffs
    }

    func recordedCalls() -> [CommitDiffCall] {
        calls
    }

    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        calls.append(CommitDiffCall(wc: wc, target: target, r1: r1, r2: r2))
        return diffs[target] ?? ""
    }
}

private actor FakeAIProviderManager: AIProviderManaging {
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
