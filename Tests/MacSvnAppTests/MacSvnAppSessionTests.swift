import XCTest
@testable import MacSvnApp
import MacSvnCore

final class MacSvnAppSessionTests: XCTestCase {
    func testBootstrapCreatesSupportFilesAndLoadsDefaultSettings() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macsvn-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let session = try await MacSvnAppSession.bootstrap(supportDirectory: root)

        let settings = await session.settingsStore.settings()
        XCTAssertEqual(settings.logBatchSize, 100)
        XCTAssertEqual(settings.processTimeout, 120)

        let workspaces = try await session.workspaceStore.load()
        XCTAssertTrue(workspaces.isEmpty)

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("settings.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("workspaces.json").path))

        // Wave F：Git 迁移 / 菜单栏依赖应在 bootstrap 中可用
        _ = await session.gitMigrationService
        _ = await session.gitMigrationSourceAnalyzer
        _ = await session.gitMigrationSyncService
        _ = await session.menuBarStatusSnapshotter
        let pollMinutes = await session.menuBarPollIntervalMinutes
        XCTAssertGreaterThanOrEqual(pollMinutes, 1)
    }

    func testBootstrapUsesConfiguredSvnPathWhenAvailable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macsvn-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let settingsURL = root.appendingPathComponent("settings.json")
        let configured = AppSettings(svnPath: "/opt/homebrew/bin/svn", logBatchSize: 50)
        let data = try JSONEncoder().encode(SettingsFile(settings: configured))
        try data.write(to: settingsURL)

        let session = try await MacSvnAppSession.bootstrap(supportDirectory: root)
        let settings = await session.settingsStore.settings()
        let executablePath = await session.svnExecutablePath
        XCTAssertEqual(settings.svnPath, "/opt/homebrew/bin/svn")
        XCTAssertEqual(settings.logBatchSize, 50)
        XCTAssertEqual(executablePath, "/opt/homebrew/bin/svn")
    }

    func testBootstrapInjectsConfiguredShelvingVersionIntoOfficialClient() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macsvn-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let settingsURL = root.appendingPathComponent("settings.json")
        let configured = AppSettings(svnPath: "/usr/bin/false", shelvingVersion: .v2)
        let data = try JSONEncoder().encode(SettingsFile(settings: configured))
        try data.write(to: settingsURL)

        let session = try await MacSvnAppSession.bootstrap(supportDirectory: root)
        let availability = await session.shelveService.officialAvailability(wc: root)

        guard case .unavailable(let version, _) = availability else {
            return XCTFail("Expected unavailable shelving client backed by /usr/bin/false")
        }
        XCTAssertEqual(version, .v2)
    }

    func testBootstrapExportsConfiguredFinderSyncCacheMode() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macsvn-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var configured = AppSettings()
        configured.finderSyncCacheMode = .shell
        let data = try JSONEncoder().encode(SettingsFile(settings: configured))
        try data.write(to: root.appendingPathComponent("settings.json"))

        _ = try await MacSvnAppSession.bootstrap(supportDirectory: root)

        let configuration = try FinderSyncRootsExporter.loadConfiguration(
            from: FinderSyncRootsExporter.fileURL(in: root)
        )
        XCTAssertEqual(configuration.cacheMode, .shell)
    }

    func testBootstrapExportsConfiguredFinderSyncOverlaySettings() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macsvn-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var configured = AppSettings()
        configured.finderSyncOverlaySettings = FinderSyncOverlaySettings(
            includedPaths: ["/tmp/include"],
            excludedPaths: ["/tmp/include/.build"],
            enabledBadges: [.normal, .modified]
        )
        let data = try JSONEncoder().encode(SettingsFile(settings: configured))
        try data.write(to: root.appendingPathComponent("settings.json"))

        _ = try await MacSvnAppSession.bootstrap(supportDirectory: root)

        let configuration = try FinderSyncRootsExporter.loadConfiguration(
            from: FinderSyncRootsExporter.fileURL(in: root)
        )
        XCTAssertEqual(configuration.overlaySettings, configured.finderSyncOverlaySettings)
    }

    func testBootstrapExportsConfiguredFinderSyncContextMenuSettings() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macsvn-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var configured = AppSettings()
        configured.finderSyncContextMenuSettings = FinderSyncContextMenuSettings(
            promotedCommandIDs: [.copyMove, .update],
            hideMenusForUnversionedItems: true,
            excludedPaths: ["/tmp/private"]
        )
        let data = try JSONEncoder().encode(SettingsFile(settings: configured))
        try data.write(to: root.appendingPathComponent("settings.json"))

        _ = try await MacSvnAppSession.bootstrap(supportDirectory: root)

        let configuration = try FinderSyncRootsExporter.loadConfiguration(
            from: FinderSyncRootsExporter.fileURL(in: root)
        )
        XCTAssertEqual(
            configuration.contextMenuSettings,
            configured.finderSyncContextMenuSettings
        )
    }
}
