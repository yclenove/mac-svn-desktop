import Foundation
import XCTest
@testable import MacSvnCore

final class AIProviderSettingsViewModelTests: XCTestCase {
    @MainActor
    func testLoadSaveDefaultDeleteAndConnectionTestUpdateState() async {
        let provider = AIProvider(
            name: "Local",
            kind: .ollama,
            baseURL: "http://localhost:11434",
            model: "llama3",
            apiKeyRef: nil,
            maxTokens: 4096,
            temperature: 0.1
        )
        let testResult = AIProviderConnectionTestResult(
            providerID: provider.id,
            latencyMilliseconds: 42,
            promptTokens: 3,
            completionTokens: 2
        )
        let manager = FakeAIProviderManager(providers: [provider])
        let tester = FakeAIProviderConnectivityTester(result: .success(testResult))
        let viewModel = AIProviderSettingsViewModel(manager: manager, connectivityTester: tester)

        await viewModel.loadProviders()
        XCTAssertEqual(viewModel.providers, [provider])

        await viewModel.saveProvider(provider, makeDefault: true)
        XCTAssertEqual(viewModel.providers, [provider])

        await viewModel.setDefaultProvider(provider.id)
        XCTAssertEqual(viewModel.defaultProviderID, provider.id)

        await viewModel.testConnection(provider)
        XCTAssertEqual(viewModel.connectionTestResult, testResult)
        XCTAssertEqual(viewModel.state, .idle)

        await viewModel.deleteProvider(provider.id)
        XCTAssertEqual(viewModel.providers, [])
        XCTAssertNil(viewModel.defaultProviderID)
    }

    @MainActor
    func testProviderFailureStoresError() async {
        let manager = FakeAIProviderManager(error: AIProviderError.emptyName)
        let viewModel = AIProviderSettingsViewModel(
            manager: manager,
            connectivityTester: FakeAIProviderConnectivityTester()
        )

        await viewModel.loadProviders()

        XCTAssertEqual(viewModel.state, .error(String(describing: AIProviderError.emptyName)))
    }

    @MainActor
    func testConnectionFailureStoresErrorAndClearsPreviousResult() async {
        let provider = AIProvider(
            name: "Claude",
            kind: .anthropic,
            baseURL: "https://api.anthropic.com",
            model: "claude",
            apiKeyRef: "key",
            maxTokens: 4096,
            temperature: 0.5
        )
        let successResult = AIProviderConnectionTestResult(
            providerID: provider.id,
            latencyMilliseconds: 10,
            promptTokens: 1,
            completionTokens: 1
        )
        let tester = FakeAIProviderConnectivityTester(results: [
            .success(successResult),
            .failure(AIProviderConnectivityError.pingFailed("offline"))
        ])
        let viewModel = AIProviderSettingsViewModel(
            manager: FakeAIProviderManager(providers: [provider]),
            connectivityTester: tester
        )

        await viewModel.loadProviders()
        await viewModel.testConnection(provider)
        XCTAssertEqual(viewModel.connectionTestResult, successResult)

        await viewModel.testConnection(provider)

        XCTAssertNil(viewModel.connectionTestResult)
        XCTAssertEqual(viewModel.state, .error(String(describing: AIProviderConnectivityError.pingFailed("offline"))))
    }
}

private actor FakeAIProviderManager: AIProviderManaging {
    private var providers: [AIProvider]
    private var defaultID: UUID?
    private let error: Error?

    init(providers: [AIProvider] = [], error: Error? = nil) {
        self.providers = providers
        self.defaultID = providers.first?.id
        self.error = error
    }

    func loadProviders() async throws -> [AIProvider] {
        if let error {
            throw error
        }
        return providers
    }

    func saveProvider(_ provider: AIProvider, makeDefault: Bool) async throws -> AIProvider {
        if let error {
            throw error
        }
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
        } else {
            providers.append(provider)
        }
        if makeDefault || defaultID == nil {
            defaultID = provider.id
        }
        return provider
    }

    func deleteProvider(id: UUID) async throws {
        if let error {
            throw error
        }
        providers.removeAll { $0.id == id }
        if defaultID == id {
            defaultID = providers.first?.id
        }
    }

    func setDefaultProvider(id: UUID) async throws -> AIProvider {
        if let error {
            throw error
        }
        guard let provider = providers.first(where: { $0.id == id }) else {
            throw AIProviderError.providerNotFound(id)
        }
        defaultID = id
        return provider
    }

    func defaultProviderID() async -> UUID? {
        defaultID
    }
}

private actor FakeAIProviderConnectivityTester: AIProviderConnectivityTesting {
    private var results: [Result<AIProviderConnectionTestResult, Error>]

    init(result: Result<AIProviderConnectionTestResult, Error> = .failure(AIProviderConnectivityError.pingFailed("not configured"))) {
        self.results = [result]
    }

    init(results: [Result<AIProviderConnectionTestResult, Error>]) {
        self.results = results
    }

    func testConnection(provider: AIProvider) async throws -> AIProviderConnectionTestResult {
        let result = results.isEmpty
            ? Result.failure(AIProviderConnectivityError.pingFailed("missing result"))
            : results.removeFirst()
        return try result.get()
    }
}
