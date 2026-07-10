import XCTest
@testable import MacSvnApp
@testable import MacSvnCore

@MainActor
final class MacSvnMenuBarControllerTests: XCTestCase {
    func testLocalFSEventTriggersDebouncedRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("menubar-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let wcPath = directory.appendingPathComponent("wc", isDirectory: true)
        try FileManager.default.createDirectory(
            at: wcPath.appendingPathComponent(".svn", isDirectory: true),
            withIntermediateDirectories: true
        )

        let store = WorkspaceStore(fileURL: directory.appendingPathComponent("workspaces.json"))
        let record = try await store.addWorkingCopy(
            localPath: wcPath,
            repoURL: "file:///repo",
            revision: Revision(1),
            name: "wc"
        )

        let snapshotter = MenuBarStatusSnapshotter(
            statusProvider: FakeMenuBarStatusProvider(),
            remoteLogProvider: FakeMenuBarLogProvider()
        )
        let watcher = FakeWorkingCopyChangeWatcher()
        let controller = MacSvnMenuBarController(
            workspaceStore: store,
            snapshotter: snapshotter,
            pollIntervalMinutes: 60,
            changeWatcher: watcher,
            localRefreshDebounceNanoseconds: 20_000_000,
            requestsNotificationPermission: false
        )

        controller.start()
        // 等待 rearmLocalWatcher
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(watcher.startCount, 1)
        XCTAssertEqual(watcher.lastPaths, [record.localPath])

        watcher.emitChange()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertGreaterThanOrEqual(controller.localRefreshTriggerCount, 1)
        controller.stop()
        XCTAssertGreaterThanOrEqual(watcher.stopCount, 1)
    }
}

private final class FakeWorkingCopyChangeWatcher: WorkingCopyChangeWatching, @unchecked Sendable {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var lastPaths: [String] = []
    private var onChange: (@Sendable () -> Void)?

    func startWatching(paths: [String], onChange: @escaping @Sendable () -> Void) {
        startCount += 1
        lastPaths = paths
        self.onChange = onChange
    }

    func stopWatching() {
        stopCount += 1
        onChange = nil
    }

    func emitChange() {
        onChange?()
    }
}

private struct FakeMenuBarStatusProvider: StatusProviding {
    func status(wc: URL) async throws -> [FileStatus] {
        [FileStatus(path: "a.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false)]
    }
}

private struct FakeMenuBarLogProvider: MenuBarRemoteLogProviding {
    func remoteLogFromHead(url: String, batch: Int, verbose: Bool, auth: Credential?) async throws -> [LogEntry] {
        []
    }
}
