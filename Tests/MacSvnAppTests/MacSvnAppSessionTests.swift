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
}
