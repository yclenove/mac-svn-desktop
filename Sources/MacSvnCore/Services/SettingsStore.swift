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
        cachedSettings = settings
        try store.save(SettingsFile(settings: settings))
    }

    @discardableResult
    public func reset() throws -> AppSettings {
        let defaults = AppSettings()
        cachedSettings = defaults
        try store.save(SettingsFile(settings: defaults))
        return defaults
    }
}
