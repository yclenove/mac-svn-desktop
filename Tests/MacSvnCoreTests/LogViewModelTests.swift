import Foundation
import XCTest
@testable import MacSvnCore

final class LogViewModelTests: XCTestCase {
    @MainActor
    func testInitialLoadUsesTargetStartRevisionBatchAndVerboseFlag() async {
        let entries = [logEntry(Revision(9)), logEntry(Revision(8))]
        let provider = FakeLogProvider(results: [.success(entries)])
        let viewModel = LogViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "Sources",
            batchSize: 2,
            logProvider: provider
        )

        await viewModel.loadInitial(from: Revision(9))
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.entries.map(\.revision), [Revision(9), Revision(8)])
        XCTAssertTrue(viewModel.hasMore)
        XCTAssertEqual(calls, [
            LogCall(
                wc: URL(fileURLWithPath: "/tmp/wc"),
                target: "Sources",
                from: Revision(9),
                batch: 2,
                verbose: true,
                stopOnCopy: false
            )
        ])
    }

    @MainActor
    func testLoadMoreStartsBeforeLowestLoadedRevisionAndStopsOnShortPage() async {
        let provider = FakeLogProvider(results: [
            .success([logEntry(Revision(10)), logEntry(Revision(9))]),
            .success([logEntry(Revision(8))])
        ])
        let viewModel = LogViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: ".",
            batchSize: 2,
            logProvider: provider
        )

        await viewModel.loadInitial(from: Revision(10))
        await viewModel.loadMore()
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.entries.map(\.revision), [Revision(10), Revision(9), Revision(8)])
        XCTAssertFalse(viewModel.hasMore)
        XCTAssertEqual(calls.map(\.from), [Revision(10), Revision(8)])
    }

    @MainActor
    func testLoadMoreDoesNothingBeforeInitialLoadOrAfterEndReached() async {
        let provider = FakeLogProvider(results: [
            .success([logEntry(Revision(10))])
        ])
        let viewModel = LogViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: ".",
            batchSize: 2,
            logProvider: provider
        )

        await viewModel.loadMore()
        let callsBeforeInitialLoad = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .idle)
        XCTAssertTrue(callsBeforeInitialLoad.isEmpty)

        await viewModel.loadInitial(from: Revision(10))
        await viewModel.loadMore()
        let calls = await provider.recordedCalls()

        XCTAssertEqual(calls.map(\.from), [Revision(10)])
        XCTAssertFalse(viewModel.hasMore)
    }

    @MainActor
    func testInitialLoadSurfacesProviderErrors() async {
        let provider = FakeLogProvider(results: [.failure(SvnError.network(detail: "offline"))])
        let viewModel = LogViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: ".",
            batchSize: 2,
            logProvider: provider
        )

        await viewModel.loadInitial(from: Revision(10))

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertEqual(viewModel.entries, [])
        XCTAssertFalse(viewModel.hasMore)
    }

    @MainActor
    func testStopOnCopyIsForwardedToProvider() async {
        let provider = FakeLogProvider(results: [.success([logEntry(Revision(3))])])
        let viewModel = LogViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "branch",
            batchSize: 50,
            logProvider: provider
        )
        viewModel.stopOnCopy = true

        await viewModel.loadInitial(from: Revision(3))
        let calls = await provider.recordedCalls()

        XCTAssertEqual(calls.first?.stopOnCopy, true)
    }

    @MainActor
    func testLoadAllFetchesUntilShortPage() async {
        let provider = FakeLogProvider(results: [
            .success([logEntry(Revision(5)), logEntry(Revision(4))]),
            .success([logEntry(Revision(3)), logEntry(Revision(2))]),
            .success([logEntry(Revision(1))])
        ])
        let viewModel = LogViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: ".",
            batchSize: 2,
            logProvider: provider
        )

        await viewModel.loadInitial(from: Revision(5))
        await viewModel.loadAll()
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.entries.map(\.revision.value), [5, 4, 3, 2, 1])
        XCTAssertFalse(viewModel.hasMore)
        XCTAssertEqual(calls.count, 3)
    }

    @MainActor
    func testOnlineLoadWritesCacheAndReportsLiveSource() async {
        let entries = [logEntry(Revision(9))]
        let provider = FakeLogProvider(results: [.success(entries)])
        let cache = FakeLogCache()
        let identity = LogCacheIdentity(repositoryRoot: "file:///repo", target: "trunk")
        let viewModel = LogViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "trunk",
            batchSize: 10,
            logProvider: provider,
            logCache: cache,
            cacheIdentity: identity,
            cachePolicy: LogCachePolicy()
        )

        await viewModel.loadInitial(from: Revision(9))

        XCTAssertEqual(viewModel.dataSource, .live)
        let writes = await cache.recordedMerges()
        XCTAssertEqual(writes.map(\.entries), [entries])
        XCTAssertEqual(writes.first?.key, identity.key(stopOnCopy: false))
    }

    @MainActor
    func testNetworkFailureFallsBackToCachedEntries() async {
        let cached = [logEntry(Revision(7)), logEntry(Revision(6))]
        let updatedAt = Date(timeIntervalSince1970: 100)
        let provider = FakeLogProvider(results: [.failure(SvnError.network(detail: "offline"))])
        let cache = FakeLogCache(snapshot: LogCacheSnapshot(
            key: LogCacheKey(repositoryRoot: "file:///repo", target: "trunk", stopOnCopy: false),
            updatedAt: updatedAt,
            entries: cached
        ))
        let viewModel = LogViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "trunk",
            batchSize: 10,
            logProvider: provider,
            logCache: cache,
            cacheIdentity: LogCacheIdentity(repositoryRoot: "file:///repo", target: "trunk"),
            cachePolicy: LogCachePolicy()
        )

        await viewModel.loadInitial(from: Revision(9))

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.entries, cached)
        XCTAssertEqual(
            viewModel.dataSource,
            .fallbackCache(updatedAt: updatedAt, reason: String(describing: SvnError.network(detail: "offline")))
        )
        XCTAssertFalse(viewModel.hasMore)
    }

    @MainActor
    func testForcedOfflineReadsCacheWithoutCallingProvider() async {
        let cached = [logEntry(Revision(4))]
        let updatedAt = Date(timeIntervalSince1970: 200)
        let provider = FakeLogProvider(results: [])
        let key = LogCacheKey(repositoryRoot: "file:///repo", target: "branch", stopOnCopy: true)
        let cache = FakeLogCache(snapshot: LogCacheSnapshot(key: key, updatedAt: updatedAt, entries: cached))
        let viewModel = LogViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "branch",
            batchSize: 10,
            logProvider: provider,
            logCache: cache,
            cacheIdentity: LogCacheIdentity(repositoryRoot: "file:///repo", target: "branch"),
            cachePolicy: LogCachePolicy()
        )
        viewModel.stopOnCopy = true
        viewModel.offlineMode = true

        await viewModel.loadInitial(from: Revision(9))

        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [])
        XCTAssertEqual(viewModel.entries, cached)
        XCTAssertEqual(viewModel.dataSource, .offlineCache(updatedAt: updatedAt))
        XCTAssertFalse(viewModel.hasMore)
    }
}

private struct LogCall: Equatable, Sendable {
    let wc: URL
    let target: String
    let from: Revision
    let batch: Int
    let verbose: Bool
    let stopOnCopy: Bool
}

private actor FakeLogProvider: LogProviding {
    private var results: [Result<[LogEntry], Error>]
    private var calls: [LogCall] = []

    init(results: [Result<[LogEntry], Error>]) {
        self.results = results
    }

    func recordedCalls() -> [LogCall] {
        calls
    }

    func log(
        wc: URL,
        target: String,
        from: Revision,
        batch: Int,
        verbose: Bool,
        stopOnCopy: Bool
    ) async throws -> [LogEntry] {
        calls.append(
            LogCall(
                wc: wc,
                target: target,
                from: from,
                batch: batch,
                verbose: verbose,
                stopOnCopy: stopOnCopy
            )
        )
        guard !results.isEmpty else {
            return []
        }

        return try results.removeFirst().get()
    }
}

private struct FakeLogCacheMerge: Equatable, Sendable {
    let entries: [LogEntry]
    let key: LogCacheKey
}

private actor FakeLogCache: LogCaching {
    private let storedSnapshot: LogCacheSnapshot?
    private var merges: [FakeLogCacheMerge] = []

    init(snapshot: LogCacheSnapshot? = nil) {
        self.storedSnapshot = snapshot
    }

    func recordedMerges() -> [FakeLogCacheMerge] { merges }

    func snapshot(
        for key: LogCacheKey,
        policy: LogCachePolicy,
        now: Date
    ) async throws -> LogCacheSnapshot? {
        storedSnapshot?.key == key ? storedSnapshot : nil
    }

    func merge(
        entries: [LogEntry],
        for key: LogCacheKey,
        policy: LogCachePolicy,
        now: Date
    ) async throws {
        merges.append(FakeLogCacheMerge(entries: entries, key: key))
    }
}

private func logEntry(_ revision: Revision) -> LogEntry {
    LogEntry(
        revision: revision,
        author: "yangchao",
        date: nil,
        message: "r\(revision.value)",
        changedPaths: [
            ChangedPath(
                path: "/trunk/file-\(revision.value).swift",
                action: .modified,
                kind: "file",
                copyFromPath: nil,
                copyFromRevision: nil
            )
        ]
    )
}
