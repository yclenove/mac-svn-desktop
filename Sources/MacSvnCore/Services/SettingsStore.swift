import Foundation

public actor SettingsStore {
    private let store: PersistenceStore<SettingsFile>
    private var cachedSettings = AppSettings()

    public init(fileURL: URL) {
        self.store = PersistenceStore(fileURL: fileURL, defaultValue: SettingsFile())
    }

    public func load() throws -> AppSettings {
        let file = try store.load()
        cachedSettings = file.settings
        return cachedSettings
    }

    public func settings() -> AppSettings {
        cachedSettings
    }

    public func update(_ settings: AppSettings) throws {
        try store.save(SettingsFile(settings: settings))
        cachedSettings = settings
    }

    @discardableResult
    public func reset() throws -> AppSettings {
        let defaults = AppSettings()
        try store.save(SettingsFile(settings: defaults))
        cachedSettings = defaults
        return defaults
    }
}
