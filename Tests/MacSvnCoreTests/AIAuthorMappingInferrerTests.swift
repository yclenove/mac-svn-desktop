import Foundation
import XCTest
@testable import MacSvnCore

final class AIAuthorMappingInferrerTests: XCTestCase {
    func testInferMappingsParsesJSONAndFiltersUnknownUsers() async throws {
        let provider = AIProvider(
            name: "Ark",
            kind: .openAICompatible,
            baseURL: "https://ark.example/v3",
            model: "doubao",
            apiKeyRef: "keychain://ark",
            maxTokens: 8_000,
            temperature: 0.1
        )
        let llm = FakeAuthorInferLLMClient(responses: [
            AILLMResponse(
                content: """
                {
                  "mappings": [
                    {"svnUsername":"zhangsan","gitName":"张三","gitEmail":"zhangsan@acme.com"},
                    {"svnUsername":"ghost","gitName":"Ghost","gitEmail":"ghost@acme.com"},
                    {"svnUsername":"lisi","gitName":"","gitEmail":"lisi@acme.com"}
                  ]
                }
                """,
                promptTokens: 40,
                completionTokens: 20
            )
        ])
        let inferrer = AIAuthorMappingInferrer(
            providerManager: FakeAuthorInferProviderManager(providers: [provider]),
            llmClient: llm
        )

        let draft = try await inferrer.inferMappings(
            authors: [
                GitMigrationAuthor(svnUsername: "zhangsan"),
                GitMigrationAuthor(svnUsername: "lisi")
            ],
            emailDomain: "acme.com",
            privacySettings: AIPrivacySettings()
        )
        let calls = await llm.recordedCalls()
        let prompt = calls[0].messages.map(\.content).joined(separator: "\n")

        XCTAssertEqual(draft.providerID, provider.id)
        XCTAssertEqual(draft.promptCount, 1)
        XCTAssertEqual(draft.suggestions, [
            AIAuthorMappingSuggestion(
                svnUsername: "zhangsan",
                gitName: "张三",
                gitEmail: "zhangsan@acme.com"
            )
        ])
        XCTAssertTrue(prompt.contains("acme.com"))
        XCTAssertTrue(prompt.contains("zhangsan"))
    }

    func testEmptyAuthorListThrows() async {
        let inferrer = AIAuthorMappingInferrer(
            providerManager: FakeAuthorInferProviderManager(providers: []),
            llmClient: FakeAuthorInferLLMClient(responses: [])
        )

        do {
            _ = try await inferrer.inferMappings(
                authors: [],
                emailDomain: "acme.com",
                privacySettings: AIPrivacySettings()
            )
            XCTFail("expected emptyAuthorList")
        } catch AIAuthorMappingInferenceError.emptyAuthorList {
            // expected
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}

private struct FakeAuthorInferProviderManager: AIProviderManaging {
    let providers: [AIProvider]
    var defaultID: UUID?

    init(providers: [AIProvider]) {
        self.providers = providers
        self.defaultID = providers.first?.id
    }

    func loadProviders() async throws -> [AIProvider] { providers }

    func saveProvider(_ provider: AIProvider, makeDefault: Bool) async throws -> AIProvider { provider }

    func deleteProvider(id: UUID) async throws {}

    func setDefaultProvider(id: UUID) async throws -> AIProvider {
        providers.first(where: { $0.id == id }) ?? providers[0]
    }

    func defaultProviderID() async -> UUID? { defaultID }
}

private actor FakeAuthorInferLLMClient: LLMChatting {
    private var responses: [AILLMResponse]
    private var calls: [(provider: AIProvider, messages: [AILLMMessage])] = []

    init(responses: [AILLMResponse]) {
        self.responses = responses
    }

    func recordedCalls() -> [(provider: AIProvider, messages: [AILLMMessage])] {
        calls
    }

    func chat(provider: AIProvider, messages: [AILLMMessage]) async throws -> AILLMResponse {
        calls.append((provider, messages))
        guard !responses.isEmpty else {
            throw AIAuthorMappingInferenceError.emptyModelResponse
        }
        return responses.removeFirst()
    }
}
