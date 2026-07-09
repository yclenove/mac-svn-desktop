import Foundation
import Observation

public protocol AIProviderConnectivityTesting: Sendable {
    func testConnection(provider: AIProvider) async throws -> AIProviderConnectionTestResult
}

public enum AIProviderSettingsState: Equatable, Sendable {
    case idle
    case loading
    case saving
    case testing
    case error(String)
}

@MainActor
@Observable
public final class AIProviderSettingsViewModel {
    private let manager: any AIProviderManaging
    private let connectivityTester: any AIProviderConnectivityTesting

    public private(set) var state: AIProviderSettingsState = .idle
    public private(set) var providers: [AIProvider] = []
    public private(set) var defaultProviderID: UUID?
    public private(set) var connectionTestResult: AIProviderConnectionTestResult?

    public init(
        manager: any AIProviderManaging,
        connectivityTester: any AIProviderConnectivityTesting
    ) {
        self.manager = manager
        self.connectivityTester = connectivityTester
    }

    public func loadProviders() async {
        state = .loading

        do {
            providers = try await manager.loadProviders()
            defaultProviderID = await manager.defaultProviderID()
            state = .idle
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func saveProvider(_ provider: AIProvider, makeDefault: Bool) async {
        state = .saving

        do {
            let saved = try await manager.saveProvider(provider, makeDefault: makeDefault)
            upsert(saved)
            defaultProviderID = await manager.defaultProviderID()
            state = .idle
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func deleteProvider(_ id: UUID) async {
        state = .saving

        do {
            try await manager.deleteProvider(id: id)
            providers.removeAll { $0.id == id }
            defaultProviderID = await manager.defaultProviderID()
            state = .idle
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func setDefaultProvider(_ id: UUID) async {
        state = .saving

        do {
            _ = try await manager.setDefaultProvider(id: id)
            defaultProviderID = id
            state = .idle
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func testConnection(_ provider: AIProvider) async {
        state = .testing
        connectionTestResult = nil

        do {
            connectionTestResult = try await connectivityTester.testConnection(provider: provider)
            state = .idle
        } catch {
            state = .error(String(describing: error))
        }
    }

    private func upsert(_ provider: AIProvider) {
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
        } else {
            providers.append(provider)
        }
    }
}
