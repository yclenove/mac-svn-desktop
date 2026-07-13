import Foundation
import XCTest
@testable import MacSvnCore

final class SettingsStoreTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testLoadMissingFileReturnsDefaultSettings() async throws {
        let store = makeStore(root: temporaryRoot())

        let settings = try await store.load()

        XCTAssertNil(settings.svnPath)
        XCTAssertEqual(settings.logBatchSize, 100)
        XCTAssertEqual(settings.branchLayout, BranchLayout())
        XCTAssertEqual(settings.processTimeout, 120)
        XCTAssertNil(settings.externalDiffTool)
        XCTAssertEqual(settings.logCachePolicy, LogCachePolicy())
        XCTAssertEqual(settings.finderSyncCacheMode, .defaultCache)
    }

    func testUpdatePersistsSettings() async throws {
        let root = temporaryRoot()
        let store = makeStore(root: root)
        let externalDiffTool = ExternalDiffToolConfiguration(
            name: "Kaleidoscope",
            executablePath: "/usr/local/bin/ksdiff",
            arguments: ["--wait", "{left}", "{right}"]
        )
        let updated = AppSettings(
            svnPath: "/custom/svn",
            logBatchSize: 50,
            branchLayout: BranchLayout(trunk: "main", branches: "dev/branches", tags: "releases"),
            processTimeout: 45,
            externalDiffTool: externalDiffTool
        )

        try await store.update(updated)

        let reloadedStore = makeStore(root: root)
        let reloaded = try await reloadedStore.load()
        XCTAssertEqual(reloaded, updated)
    }

    func testRevisionGraphSettingsPersistWithAppSettings() async throws {
        let root = temporaryRoot()
        let store = makeStore(root: root)
        let graphSettings = RevisionGraphSettings(
            trunkPatterns: ["main/**"],
            branchPatterns: ["work/*/**"],
            tagPatterns: ["release/*/**"],
            blendCopyColors: false,
            palette: RevisionGraphPalette(trunkHex: "#111111")
        )

        var settings = AppSettings()
        settings.revisionGraph = graphSettings
        try await store.update(settings)

        let reloaded = try await makeStore(root: root).load()
        XCTAssertEqual(reloaded.revisionGraph, graphSettings)
    }

    func testShelvingVersionDefaultsPersistsAndDecodesLegacySettings() async throws {
        XCTAssertEqual(AppSettings().shelvingVersion, .v3)

        let root = temporaryRoot()
        let store = makeStore(root: root)
        var settings = AppSettings()
        settings.shelvingVersion = .v2
        try await store.update(settings)
        let reloaded = try await makeStore(root: root).load()
        XCTAssertEqual(reloaded.shelvingVersion, .v2)

        let legacy = """
        {"version":1,"settings":{"logBatchSize":100,"branchLayout":{"trunk":"trunk","branches":"branches","tags":"tags"},"processTimeout":120}}
        """
        let decoded = try JSONDecoder().decode(SettingsFile.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.settings.shelvingVersion, .v3)
        XCTAssertEqual(decoded.settings.logCachePolicy, LogCachePolicy())
        XCTAssertEqual(decoded.settings.finderSyncCacheMode, .defaultCache)
    }

    func testLogCachePolicyPersistsWithSettings() async throws {
        let root = temporaryRoot()
        let store = makeStore(root: root)
        var settings = AppSettings()
        settings.logCachePolicy = LogCachePolicy(
            enabled: false,
            retentionDays: 14,
            maxEntriesPerTarget: 5_000
        )

        try await store.update(settings)

        let reloaded = try await makeStore(root: root).load()
        XCTAssertEqual(reloaded.logCachePolicy, settings.logCachePolicy)
    }

    func testFinderSyncCacheModePersistsWithSettings() async throws {
        let root = temporaryRoot()
        let store = makeStore(root: root)
        var settings = AppSettings()
        settings.finderSyncCacheMode = .shell

        try await store.update(settings)

        let reloaded = try await makeStore(root: root).load()
        XCTAssertEqual(reloaded.finderSyncCacheMode, .shell)
    }

    func testFinderSyncOverlaySettingsPersistWithSettings() async throws {
        let root = temporaryRoot()
        let store = makeStore(root: root)
        var settings = AppSettings()
        settings.finderSyncOverlaySettings = FinderSyncOverlaySettings(
            includedPaths: ["/tmp/include"],
            excludedPaths: ["/tmp/include/.build"],
            enabledBadges: [.modified, .normal]
        )

        try await store.update(settings)

        let reloaded = try await makeStore(root: root).load()
        XCTAssertEqual(reloaded.finderSyncOverlaySettings, settings.finderSyncOverlaySettings)
    }

    func testResetRestoresDefaults() async throws {
        let root = temporaryRoot()
        let store = makeStore(root: root)
        try await store.update(AppSettings(
            svnPath: "/custom/svn",
            logBatchSize: 50,
            branchLayout: BranchLayout(trunk: "main", branches: "dev/branches", tags: "releases"),
            processTimeout: 45,
            externalDiffTool: ExternalDiffToolConfiguration(
                name: "Beyond Compare",
                executablePath: "/Applications/Beyond Compare.app/Contents/MacOS/bcomp",
                arguments: ["{left}", "{right}"]
            )
        ))

        let defaults = try await store.reset()
        let persistedDefaults = try await makeStore(root: root).load()

        XCTAssertEqual(defaults, AppSettings())
        XCTAssertEqual(persistedDefaults, AppSettings())
    }

    private func makeStore(root: URL) -> SettingsStore {
        SettingsStore(fileURL: root.appendingPathComponent("settings.json"))
    }

    private func temporaryRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSvnCoreSettings-\(UUID().uuidString)", isDirectory: true)
        temporaryRoots.append(root)
        return root
    }
}
