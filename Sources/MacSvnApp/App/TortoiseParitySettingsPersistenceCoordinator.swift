import Foundation
import MacSvnCore

enum TortoiseParitySettingsPersistenceError: Error, CustomStringConvertible {
    case rollbackFailed(primary: String, rollback: [String])

    var description: String {
        switch self {
        case .rollbackFailed(let primary, let rollback):
            return "settings save failed: \(primary); rollback failed: \(rollback.joined(separator: "; "))"
        }
    }
}

struct TortoiseParitySettingsPersistenceCoordinator {
    let settingsStore: SettingsStore
    let historyStore: CommitMessageHistoryStore
    let configurationStore: SvnClientConfigurationStore

    func save(
        settings: AppSettings,
        managedConfiguration: SvnClientManagedConfiguration
    ) async throws {
        let originalSettings = await settingsStore.settings()
        let originalConfiguration = try configurationStore.load()
        var attemptedConfigurationUpdate = false
        var attemptedSettingsUpdate = false

        do {
            attemptedConfigurationUpdate = true
            try configurationStore.update(managedConfiguration)
            attemptedSettingsUpdate = true
            try await settingsStore.update(settings)
            try await historyStore.updateLimit(settings.dialogs.commitMessageHistoryLimit)
        } catch {
            var rollbackErrors: [String] = []
            if attemptedSettingsUpdate {
                do {
                    try await settingsStore.update(originalSettings)
                } catch {
                    rollbackErrors.append("settings.json: \(error)")
                }
            }
            if attemptedConfigurationUpdate {
                do {
                    try configurationStore.update(originalConfiguration)
                } catch {
                    rollbackErrors.append("svn config/servers: \(error)")
                }
            }
            guard rollbackErrors.isEmpty else {
                throw TortoiseParitySettingsPersistenceError.rollbackFailed(
                    primary: String(describing: error),
                    rollback: rollbackErrors
                )
            }
            throw error
        }
    }
}
