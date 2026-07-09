import Foundation

public protocol AIProviderManaging: Sendable {
    func loadProviders() async throws -> [AIProvider]
    func saveProvider(_ provider: AIProvider, makeDefault: Bool) async throws -> AIProvider
    func deleteProvider(id: UUID) async throws
    func setDefaultProvider(id: UUID) async throws -> AIProvider
    func defaultProviderID() async -> UUID?
}

public actor AIProviderStore: AIProviderManaging {
    private let store: PersistenceStore<AIProviderConfigurationFile>
    private var cachedProviders: [AIProvider] = []
    private var cachedDefaultProviderID: UUID?

    public init(fileURL: URL) {
        self.store = PersistenceStore(fileURL: fileURL, defaultValue: AIProviderConfigurationFile())
    }

    public func loadProviders() async throws -> [AIProvider] {
        let file = try store.load()
        cachedProviders = file.providers
        cachedDefaultProviderID = normalizedDefaultProviderID(file.defaultProviderID, providers: cachedProviders)
        return cachedProviders
    }

    @discardableResult
    public func saveProvider(_ provider: AIProvider, makeDefault: Bool) async throws -> AIProvider {
        let normalizedProvider = try normalized(provider)
        var providers = try await loadProviders()

        if let index = providers.firstIndex(where: { $0.id == normalizedProvider.id }) {
            providers[index] = normalizedProvider
        } else {
            providers.append(normalizedProvider)
        }

        let defaultProviderID = makeDefault || cachedDefaultProviderID == nil
            ? normalizedProvider.id
            : normalizedDefaultProviderID(cachedDefaultProviderID, providers: providers)
        try persist(providers: providers, defaultProviderID: defaultProviderID)
        return normalizedProvider
    }

    public func deleteProvider(id: UUID) async throws {
        var providers = try await loadProviders()
        guard let index = providers.firstIndex(where: { $0.id == id }) else {
            throw AIProviderError.providerNotFound(id)
        }

        providers.remove(at: index)
        let defaultProviderID = cachedDefaultProviderID == id
            ? providers.first?.id
            : normalizedDefaultProviderID(cachedDefaultProviderID, providers: providers)
        try persist(providers: providers, defaultProviderID: defaultProviderID)
    }

    @discardableResult
    public func setDefaultProvider(id: UUID) async throws -> AIProvider {
        let providers = try await loadProviders()
        guard let provider = providers.first(where: { $0.id == id }) else {
            throw AIProviderError.providerNotFound(id)
        }

        try persist(providers: providers, defaultProviderID: id)
        return provider
    }

    public func defaultProviderID() async -> UUID? {
        cachedDefaultProviderID
    }

    private func normalized(_ provider: AIProvider) throws -> AIProvider {
        let name = provider.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw AIProviderError.emptyName
        }

        let baseURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty else {
            throw AIProviderError.emptyBaseURL
        }

        let model = provider.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw AIProviderError.emptyModel
        }

        guard provider.maxTokens > 0 else {
            throw AIProviderError.invalidMaxTokens(provider.maxTokens)
        }

        guard (0...2).contains(provider.temperature) else {
            throw AIProviderError.invalidTemperature(provider.temperature)
        }

        if let dailyRequestLimit = provider.dailyRequestLimit, dailyRequestLimit <= 0 {
            throw AIProviderError.invalidDailyRequestLimit(dailyRequestLimit)
        }

        let apiKeyRef = provider.apiKeyRef?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AIProvider(
            id: provider.id,
            name: name,
            kind: provider.kind,
            baseURL: baseURL,
            model: model,
            apiKeyRef: apiKeyRef?.isEmpty == true ? nil : apiKeyRef,
            maxTokens: provider.maxTokens,
            temperature: provider.temperature,
            dailyRequestLimit: provider.dailyRequestLimit
        )
    }

    private func persist(providers: [AIProvider], defaultProviderID: UUID?) throws {
        cachedProviders = providers
        cachedDefaultProviderID = normalizedDefaultProviderID(defaultProviderID, providers: providers)
        try store.save(AIProviderConfigurationFile(
            providers: cachedProviders,
            defaultProviderID: cachedDefaultProviderID
        ))
    }

    private func normalizedDefaultProviderID(_ id: UUID?, providers: [AIProvider]) -> UUID? {
        guard !providers.isEmpty else {
            return nil
        }

        guard let id, providers.contains(where: { $0.id == id }) else {
            return providers.first?.id
        }

        return id
    }
}
