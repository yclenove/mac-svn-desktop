import Foundation
import XCTest
@testable import MacSvnCore

final class BlameViewModelTests: XCTestCase {
    @MainActor
    func testLoadBlameStoresLinesAndSelectsRevision() async {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let lines = [
            BlameLine(lineNumber: 1, revision: Revision(7), author: "yangchao", date: nil),
            BlameLine(lineNumber: 2, revision: Revision(8), author: "alice", date: nil)
        ]
        let provider = FakeBlameProvider(result: .success(lines))
        let viewModel = BlameViewModel(workingCopy: wc, target: "README.txt", provider: provider)

        await viewModel.load()
        viewModel.selectLine(2)

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.lines, lines)
        XCTAssertEqual(viewModel.selectedRevision, Revision(8))
        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [BlameProviderCall(wc: wc, target: "README.txt")])
    }

    @MainActor
    func testLoadBlameFailureClearsLinesAndStoresError() async {
        let provider = FakeBlameProvider(result: .failure(SvnError.network(detail: "offline")))
        let viewModel = BlameViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "README.txt",
            provider: provider
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertEqual(viewModel.lines, [])
        XCTAssertNil(viewModel.selectedRevision)
    }

    @MainActor
    func testHoverLineLoadsItsRevisionLog() async {
        let revision = Revision(8)
        let entry = LogEntry(
            revision: revision,
            author: "alice",
            date: nil,
            message: "修复行级问题",
            changedPaths: []
        )
        let provider = FakeBlameProvider(
            result: .success([BlameLine(lineNumber: 2, revision: revision, author: "alice", date: nil)]),
            logResult: .success(entry)
        )
        let viewModel = BlameViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "README.txt",
            provider: provider,
            logProvider: provider
        )

        await viewModel.load()
        await viewModel.loadRevisionDetails(for: 2)

        XCTAssertEqual(viewModel.hoveredLineNumber, 2)
        XCTAssertEqual(viewModel.hoveredLog, entry)
        XCTAssertNil(viewModel.hoverLogError)
        let calls = await provider.recordedLogCalls()
        XCTAssertEqual(calls, [BlameLogCall(revision: revision)])
    }

    @MainActor
    func testLoadCanUseRevisionRange() async {
        let provider = FakeBlameProvider(result: .success([]))
        let viewModel = BlameViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "README.txt",
            provider: provider,
            rangeProvider: provider
        )

        await viewModel.load(startRevision: Revision(3), endRevision: Revision(9))

        let calls = await provider.recordedRangeCalls()
        XCTAssertEqual(calls, [BlameRangeCall(start: Revision(3), end: Revision(9))])
    }
}

private struct BlameProviderCall: Equatable {
    let wc: URL
    let target: String
}

private struct BlameLogCall: Equatable {
    let revision: Revision
}

private struct BlameRangeCall: Equatable {
    let start: Revision?
    let end: Revision?
}

private actor FakeBlameProvider: BlameProviding, BlameLogProviding, BlameRangeProviding {
    private let result: Result<[BlameLine], Error>
    private let logResult: Result<LogEntry?, Error>
    private var calls: [BlameProviderCall] = []
    private var logCalls: [BlameLogCall] = []
    private var rangeCalls: [BlameRangeCall] = []

    init(result: Result<[BlameLine], Error>, logResult: Result<LogEntry?, Error> = .success(nil)) {
        self.result = result
        self.logResult = logResult
    }

    func recordedCalls() -> [BlameProviderCall] {
        calls
    }

    func recordedLogCalls() -> [BlameLogCall] {
        logCalls
    }

    func recordedRangeCalls() -> [BlameRangeCall] {
        rangeCalls
    }

    func blame(wc: URL, target: String) async throws -> [BlameLine] {
        calls.append(BlameProviderCall(wc: wc, target: target))
        return try result.get()
    }

    func logForBlame(wc: URL, target: String, revision: Revision) async throws -> LogEntry? {
        _ = (wc, target)
        logCalls.append(BlameLogCall(revision: revision))
        return try logResult.get()
    }

    func blame(
        wc: URL,
        target: String,
        startRevision: Revision?,
        endRevision: Revision?
    ) async throws -> [BlameLine] {
        _ = (wc, target)
        rangeCalls.append(BlameRangeCall(start: startRevision, end: endRevision))
        return try result.get()
    }
}
