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
                verbose: true
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
    func testInitialLoadFailureStoresErrorAndClearsEntries() async {
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
}

private struct LogCall: Equatable, Sendable {
    let wc: URL
    let target: String
    let from: Revision
    let batch: Int
    let verbose: Bool
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

    func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry] {
        calls.append(LogCall(wc: wc, target: target, from: from, batch: batch, verbose: verbose))
        guard !results.isEmpty else {
            return []
        }

        return try results.removeFirst().get()
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
