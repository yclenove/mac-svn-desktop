import Foundation
import XCTest
@testable import MacSvnCore

final class AIReleaseNotesGeneratorTests: XCTestCase {
    func testGenerateReleaseNotesParsesJSONBuildsMarkdownAndRedactsSecrets() async throws {
        let provider = AIProvider(
            name: "DeepSeek",
            kind: .openAICompatible,
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-chat",
            apiKeyRef: "keychain://deepseek",
            maxTokens: 32_000,
            temperature: 0.2
        )
        let llm = FakeReleaseNotesLLMClient(responses: [
            AILLMResponse(
                content: """
                {
                  "title": "v1.2.0",
                  "sections": [
                    {"title": "新功能", "items": ["支持支付回调"]},
                    {"title": "修复", "items": ["修复登录失败提示"]}
                  ]
                }
                """,
                promptTokens: 160,
                completionTokens: 60
            )
        ])
        let generator = AIReleaseNotesGenerator(
            providerManager: FakeReleaseNotesProviderManager(providers: [provider]),
            llmClient: llm
        )
        let entries = [
            LogEntry(
                revision: Revision(1200),
                author: "zhangsan",
                date: nil,
                message: "新增支付回调 sk-1234567890abcdef",
                changedPaths: [
                    ChangedPath(
                        path: "/trunk/payment/callback.swift",
                        action: .modified,
                        kind: "file",
                        copyFromPath: nil,
                        copyFromRevision: nil
                    )
                ]
            ),
            LogEntry(
                revision: Revision(1201),
                author: "lisi",
                date: nil,
                message: "修复登录失败提示",
                changedPaths: [
                    ChangedPath(
                        path: "/trunk/login/view.swift",
                        action: .modified,
                        kind: "file",
                        copyFromPath: nil,
                        copyFromRevision: nil
                    )
                ]
            )
        ]

        let draft = try await generator.generate(
            entries: entries,
            title: "v1.2.0",
            template: .standardMarkdown,
            privacySettings: AIPrivacySettings()
        )
        let calls = await llm.recordedCalls()
        let prompt = calls[0].messages.map(\.content).joined(separator: "\n")

        XCTAssertEqual(draft.title, "v1.2.0")
        XCTAssertEqual(draft.providerID, provider.id)
        XCTAssertEqual(draft.entryCount, 2)
        XCTAssertEqual(draft.promptCount, 1)
        XCTAssertEqual(draft.redactionMatches.map(\.ruleID), ["openai-api-key"])
        XCTAssertTrue(draft.markdown.contains("# v1.2.0"))
        XCTAssertTrue(draft.markdown.contains("## 新功能"))
        XCTAssertTrue(draft.markdown.contains("- 支持支付回调"))
        XCTAssertTrue(prompt.contains("r1200"))
        XCTAssertTrue(prompt.contains("/trunk/payment/callback.swift"))
        XCTAssertTrue(prompt.contains("***REDACTED***"))
        XCTAssertFalse(prompt.contains("sk-1234567890abcdef"))
    }
}

private struct ReleaseNotesLLMCall: Equatable, Sendable {
    let provider: AIProvider
    let messages: [AILLMMessage]
}

private actor FakeReleaseNotesLLMClient: LLMChatting {
    private var responses: [AILLMResponse]
    private var calls: [ReleaseNotesLLMCall] = []

    init(responses: [AILLMResponse]) {
        self.responses = responses
    }

    func recordedCalls() -> [ReleaseNotesLLMCall] {
        calls
    }

    func chat(provider: AIProvider, messages: [AILLMMessage]) async throws -> AILLMResponse {
        calls.append(ReleaseNotesLLMCall(provider: provider, messages: messages))
        guard !responses.isEmpty else {
            return AILLMResponse(content: "", promptTokens: nil, completionTokens: nil)
        }
        return responses.removeFirst()
    }
}

private actor FakeReleaseNotesProviderManager: AIProviderManaging {
    private let providers: [AIProvider]
    private let defaultID: UUID?

    init(providers: [AIProvider], defaultID: UUID? = nil) {
        self.providers = providers
        self.defaultID = defaultID
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
