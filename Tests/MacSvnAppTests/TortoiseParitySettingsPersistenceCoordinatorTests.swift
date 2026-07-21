import Foundation
import XCTest
@testable import MacSvnApp
@testable import MacSvnCore

final class TortoiseParitySettingsPersistenceCoordinatorTests: XCTestCase {
    func testHistoryFailureRollsBackSettingsAndSvnConfiguration() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsTransaction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let settingsStore = SettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        let originalSettings = AppSettings(general: GeneralSettings(language: .simplifiedChinese))
        try await settingsStore.update(originalSettings)
        let configurationStore = SvnClientConfigurationStore(
            directoryURL: root.appendingPathComponent("subversion", isDirectory: true)
        )
        let originalManaged = SvnClientManagedConfiguration(
            globalIgnorePatterns: ["*.old"],
            useCommitTimes: false,
            network: SvnNetworkSettings()
        )
        try configurationStore.update(originalManaged)
        let historyPath = root.appendingPathComponent("history.json")
        try FileManager.default.createDirectory(at: historyPath, withIntermediateDirectories: true)
        let coordinator = TortoiseParitySettingsPersistenceCoordinator(
            settingsStore: settingsStore,
            historyStore: CommitMessageHistoryStore(fileURL: historyPath),
            configurationStore: configurationStore
        )
        let desiredSettings = AppSettings(
            general: GeneralSettings(language: .english),
            dialogs: DialogSettings(commitMessageHistoryLimit: 3),
            network: SvnNetworkSettings(proxy: SvnProxySettings(
                enabled: true,
                host: "proxy.example.com",
                port: 3128
            ))
        )
        let desiredManaged = SvnClientManagedConfiguration(
            globalIgnorePatterns: ["*.new"],
            useCommitTimes: true,
            network: desiredSettings.network
        )

        do {
            try await coordinator.save(
                settings: desiredSettings,
                managedConfiguration: desiredManaged
            )
            XCTFail("Expected history persistence to fail")
        } catch {
            XCTAssertFalse(String(describing: error).isEmpty)
        }

        let rolledBackSettings = await settingsStore.settings()
        XCTAssertEqual(rolledBackSettings, originalSettings)
        XCTAssertEqual(try configurationStore.load(), originalManaged)
    }
}
