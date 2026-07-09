import Foundation
import XCTest
@testable import MacSvnCore

final class AIProviderStoreTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testLoadMissingFileReturnsEmptyProviders() async throws {
        let store = makeStore()

        let providers = try await store.loadProviders()
        let defaultProviderID = await store.defaultProviderID()

        XCTAssertEqual(providers, [])
        XCTAssertNil(defaultProviderID)
    }

    func testSaveProviderPersistsApiKeyReferenceWithoutSecretValue() async throws {
        let root = temporaryRoot()
        let store = makeStore(root: root)
        let provider = AIProvider(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: " DeepSeek ",
            kind: .openAICompatible,
            baseURL: " https://api.deepseek.com/v1 ",
            model: " deepseek-chat ",
            apiKeyRef: " keychain://deepseek ",
            maxTokens: 32_000,
            temperature: 0.2,
            dailyRequestLimit: 100
        )

        let saved = try await store.saveProvider(provider, makeDefault: true)

        XCTAssertEqual(saved.name, "DeepSeek")
        XCTAssertEqual(saved.baseURL, "https://api.deepseek.com/v1")
        XCTAssertEqual(saved.model, "deepseek-chat")
        XCTAssertEqual(saved.apiKeyRef, "keychain://deepseek")
        XCTAssertEqual(saved.dailyRequestLimit, 100)
        let defaultProviderID = await store.defaultProviderID()
        XCTAssertEqual(defaultProviderID, saved.id)

        let data = try Data(contentsOf: root.appendingPathComponent("ai-providers.json"))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("keychain"))
        XCTAssertFalse(json.contains("sk-secret"))

        let reloaded = try await makeStore(root: root).loadProviders()
        XCTAssertEqual(reloaded, [saved])
    }

    func testSaveProviderUpsertsByIDAndKeepsDefault() async throws {
        let store = makeStore()
        let id = UUID()
        let first = AIProvider(
            id: id,
            name: "Kimi",
            kind: .openAICompatible,
            baseURL: "https://api.moonshot.cn/v1",
            model: "moonshot-v1",
            apiKeyRef: "keychain://kimi",
            maxTokens: 16_000,
            temperature: 0.4
        )
        var updated = first
        updated.model = "moonshot-v2"

        _ = try await store.saveProvider(first, makeDefault: true)
        let saved = try await store.saveProvider(updated, makeDefault: false)
        let providers = try await store.loadProviders()
        let defaultProviderID = await store.defaultProviderID()

        XCTAssertEqual(saved.model, "moonshot-v2")
        XCTAssertEqual(providers, [saved])
        XCTAssertEqual(defaultProviderID, id)
    }

    func testDeleteDefaultProviderFallsBackToRemainingProvider() async throws {
        let store = makeStore()
        let first = try await store.saveProvider(
            AIProvider(
                name: "Claude",
                kind: .anthropic,
                baseURL: "https://api.anthropic.com",
                model: "claude-3-5-sonnet",
                apiKeyRef: "keychain://claude",
                maxTokens: 8192,
                temperature: 0.5
            ),
            makeDefault: true
        )
        let second = try await store.saveProvider(
            AIProvider(
                name: "Ollama",
                kind: .ollama,
                baseURL: "http://localhost:11434",
                model: "llama3",
                apiKeyRef: nil,
                maxTokens: 4096,
                temperature: 0.1
            ),
            makeDefault: false
        )

        try await store.deleteProvider(id: first.id)
        let providers = try await store.loadProviders()
        let defaultProviderID = await store.defaultProviderID()

        XCTAssertEqual(providers, [second])
        XCTAssertEqual(defaultProviderID, second.id)
    }

    func testSetDefaultProviderRejectsMissingID() async throws {
        let store = makeStore()
        let missingID = UUID()

        do {
            _ = try await store.setDefaultProvider(id: missingID)
            XCTFail("Expected missing provider")
        } catch let error as AIProviderError {
            XCTAssertEqual(error, .providerNotFound(missingID))
        } catch {
            XCTFail("Expected AIProviderError, got \(error)")
        }
    }

    func testSaveProviderRejectsInvalidLimitsAndMissingRequiredFields() async throws {
        let store = makeStore()

        try await assertSaveThrows(
            AIProvider(
                name: " ",
                kind: .anthropic,
                baseURL: "https://api.anthropic.com",
                model: "claude",
                apiKeyRef: "key",
                maxTokens: 1,
                temperature: 0.5
            ),
            expected: .emptyName,
            store: store
        )
        try await assertSaveThrows(
            AIProvider(
                name: "Claude",
                kind: .anthropic,
                baseURL: " ",
                model: "claude",
                apiKeyRef: "key",
                maxTokens: 1,
                temperature: 0.5
            ),
            expected: .emptyBaseURL,
            store: store
        )
        try await assertSaveThrows(
            AIProvider(
                name: "Claude",
                kind: .anthropic,
                baseURL: "https://api.anthropic.com",
                model: " ",
                apiKeyRef: "key",
                maxTokens: 1,
                temperature: 0.5
            ),
            expected: .emptyModel,
            store: store
        )
        try await assertSaveThrows(
            AIProvider(
                name: "Claude",
                kind: .anthropic,
                baseURL: "https://api.anthropic.com",
                model: "claude",
                apiKeyRef: "key",
                maxTokens: 0,
                temperature: 0.5
            ),
            expected: .invalidMaxTokens(0),
            store: store
        )
        try await assertSaveThrows(
            AIProvider(
                name: "Claude",
                kind: .anthropic,
                baseURL: "https://api.anthropic.com",
                model: "claude",
                apiKeyRef: "key",
                maxTokens: 1,
                temperature: 3
            ),
            expected: .invalidTemperature(3),
            store: store
        )
        try await assertSaveThrows(
            AIProvider(
                name: "Claude",
                kind: .anthropic,
                baseURL: "https://api.anthropic.com",
                model: "claude",
                apiKeyRef: "key",
                maxTokens: 1,
                temperature: 0.5,
                dailyRequestLimit: 0
            ),
            expected: .invalidDailyRequestLimit(0),
            store: store
        )
    }

    private func assertSaveThrows(
        _ provider: AIProvider,
        expected: AIProviderError,
        store: AIProviderStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        do {
            _ = try await store.saveProvider(provider, makeDefault: false)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as AIProviderError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected AIProviderError, got \(error)", file: file, line: line)
        }
    }

    private func makeStore(root: URL? = nil) -> AIProviderStore {
        let root = root ?? temporaryRoot()
        return AIProviderStore(fileURL: root.appendingPathComponent("ai-providers.json"))
    }

    private func temporaryRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSvnCoreAIProviders-\(UUID().uuidString)", isDirectory: true)
        temporaryRoots.append(root)
        return root
    }
}
