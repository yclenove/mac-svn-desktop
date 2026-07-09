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
