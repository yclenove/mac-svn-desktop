import Foundation
import XCTest
@testable import MacSvnCore

final class DiffViewModelTests: XCTestCase {
    @MainActor
    func testLoadUnifiedDiffPassesTargetRevisionRangeAndClassifiesLines() async {
        let diff = """
        Index: a.swift
        ===================================================================
        --- a.swift\t(revision 1)
        +++ a.swift\t(working copy)
        @@ -1,2 +1,2 @@
         let unchanged = true
        -old
        +new
        \\ No newline at end of file
        """
        let provider = FakeDiffProvider(result: .success(diff))
        let viewModel = DiffViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            diffProvider: provider
        )

        await viewModel.load(target: "a.swift", r1: Revision(1), r2: Revision(2))
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.diffText, diff)
        XCTAssertEqual(viewModel.lines.map(\.kind), [
            .metadata, .metadata, .metadata, .metadata,
            .hunk, .context, .deletion, .addition, .noNewlineMarker
        ])
        XCTAssertEqual(calls, [
            DiffCall(
                wc: URL(fileURLWithPath: "/tmp/wc"),
                target: "a.swift",
                r1: Revision(1),
                r2: Revision(2)
            )
        ])
    }

    @MainActor
    func testBinaryDiffStoresUnsupportedStateAndLocalFileDetails() async throws {
        let workingCopy = try makeTemporaryDirectory()
        let fileURL = workingCopy.appendingPathComponent("image.bin")
        try Data([1, 2, 3, 4]).write(to: fileURL)
        let provider = FakeDiffProvider(result: .success("Cannot display: file marked as a binary type.\n"))
        let viewModel = DiffViewModel(workingCopy: workingCopy, diffProvider: provider)

        await viewModel.load(target: "image.bin")

        guard case .binaryUnsupported(let details) = viewModel.state else {
            return XCTFail("Expected binary unsupported state, got \(viewModel.state)")
        }
        XCTAssertEqual(details?.size, 4)
        XCTAssertNotNil(details?.modifiedAt)
        XCTAssertEqual(viewModel.diffText, "Cannot display: file marked as a binary type.\n")
        XCTAssertEqual(viewModel.lines, [])
    }

    @MainActor
    func testDiffFailureStoresErrorAndClearsLines() async {
        let provider = FakeDiffProvider(result: .failure(SvnError.network(detail: "offline")))
        let viewModel = DiffViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            diffProvider: provider
        )

        await viewModel.load(target: "a.swift")

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertEqual(viewModel.diffText, "")
        XCTAssertEqual(viewModel.lines, [])
    }

    @MainActor
    func testLoadSkipsLineParsingForOversizedDiff() async {
        let oversized = String(
            repeating: "+line\n",
            count: (DiffPerformanceLimits.maxParseCharacterCount / 6) + 10
        )
        XCTAssertGreaterThan(oversized.count, DiffPerformanceLimits.maxParseCharacterCount)

        let provider = FakeDiffProvider(result: .success(oversized))
        let viewModel = DiffViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            diffProvider: provider
        )

        await viewModel.load(target: "big.swift")

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.diffText, oversized)
        XCTAssertTrue(viewModel.lines.isEmpty)
        XCTAssertTrue(viewModel.sideBySideRows.isEmpty)
    }

    func testParseSideBySideRowsAlignsContextModificationsAndSingleSidedChanges() {
        let diff = """
        Index: a.swift
        ===================================================================
        --- a.swift\t(revision 1)
        +++ a.swift\t(working copy)
        @@ -1,4 +1,5 @@
         context
        -old name = foo
        -old only
        +new name = bar
        +new only
        +added only
         tail
        """

        let rows = DiffViewModel.parseSideBySideRows(diff)

        XCTAssertEqual(rows.map(\.kind), [
            .hunk,
            .context,
            .modification,
            .modification,
            .addition,
            .context
        ])
        XCTAssertEqual(rows[1].left?.lineNumber, 1)
        XCTAssertEqual(rows[1].right?.lineNumber, 1)
        XCTAssertEqual(rows[2].left?.text, "old name = foo")
        XCTAssertEqual(rows[2].right?.text, "new name = bar")
        XCTAssertEqual(rows[2].left?.lineNumber, 2)
        XCTAssertEqual(rows[2].right?.lineNumber, 2)
        XCTAssertEqual(rows[4].left, nil)
        XCTAssertEqual(rows[4].right?.text, "added only")
        XCTAssertEqual(rows[4].right?.lineNumber, 4)
        XCTAssertEqual(rows[5].left?.lineNumber, 4)
        XCTAssertEqual(rows[5].right?.lineNumber, 5)
    }

    func testSideBySideModifiedRowsExposeInlineChangedSpans() {
        let diff = """
        @@ -1,1 +1,1 @@
        -abc
        +axc
        """

        let rows = DiffViewModel.parseSideBySideRows(diff)

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1].kind, .modification)
        XCTAssertEqual(rows[1].left?.inlineSpans, [
            InlineDiffSpan(start: 1, length: 1, kind: .changed)
        ])
        XCTAssertEqual(rows[1].right?.inlineSpans, [
            InlineDiffSpan(start: 1, length: 1, kind: .changed)
        ])
    }

    func testSideBySideColumnTextsPreserveAlignedRowsWithoutPerLineViews() {
        let rows = DiffViewModel.parseSideBySideRows("""
        @@ -1,2 +1,2 @@
        -old
        +new
         same
        """)

        let columns = DiffViewModel.sideBySideColumnTexts(rows)

        XCTAssertEqual(columns.left.components(separatedBy: "\n").count, 3)
        XCTAssertEqual(columns.right.components(separatedBy: "\n").count, 3)
        XCTAssertTrue(columns.left.contains("1  old"))
        XCTAssertTrue(columns.right.contains("1  new"))
        XCTAssertTrue(columns.left.contains("2  same"))
        XCTAssertTrue(columns.right.contains("2  same"))
    }

    @MainActor
    func testLoadUnifiedDiffAlsoBuildsSideBySideRows() async {
        let diff = """
        @@ -1,1 +1,1 @@
        -old
        +new
        """
        let provider = FakeDiffProvider(result: .success(diff))
        let viewModel = DiffViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            diffProvider: provider
        )

        await viewModel.load(target: "a.swift")

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.sideBySideRows.map(\.kind), [.hunk, .modification])
        XCTAssertEqual(viewModel.sideBySideRows[1].left?.text, "old")
        XCTAssertEqual(viewModel.sideBySideRows[1].right?.text, "new")
    }

    @MainActor
    func testBinaryAndFailedDiffClearSideBySideRows() async {
        let binaryProvider = FakeDiffProvider(result: .success("Binary files differ\n"))
        let binaryViewModel = DiffViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            diffProvider: binaryProvider
        )

        await binaryViewModel.load(target: "image.bin")
        XCTAssertEqual(binaryViewModel.sideBySideRows, [])

        let failingProvider = FakeDiffProvider(result: .failure(SvnError.network(detail: "offline")))
        let failingViewModel = DiffViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            diffProvider: failingProvider
        )

        await failingViewModel.load(target: "a.swift")
        XCTAssertEqual(failingViewModel.sideBySideRows, [])
    }

    @MainActor
    func testOpenExternalDiffStoresLaunchResultAndPassesArguments() async {
        let result = ExternalDiffLaunchResult(
            leftFile: URL(fileURLWithPath: "/tmp/base.txt"),
            rightFile: URL(fileURLWithPath: "/tmp/wc/a.swift"),
            processResult: ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01)
        )
        let opener = FakeExternalDiffOpener(result: .success(result))
        let tool = ExternalDiffToolConfiguration(
            name: "Kaleidoscope",
            executablePath: "/usr/local/bin/ksdiff",
            arguments: ["{left}", "{right}"]
        )
        let workingCopy = URL(fileURLWithPath: "/tmp/wc")
        let viewModel = DiffViewModel(
            workingCopy: workingCopy,
            diffProvider: FakeDiffProvider(result: .success("")),
            externalDiffOpener: opener
        )

        await viewModel.openExternalDiff(target: "a.swift", tool: tool, r1: Revision(1), r2: Revision(2))
        let calls = await opener.recordedCalls()

        XCTAssertEqual(viewModel.externalDiffState, .opened(result))
        XCTAssertEqual(calls, [
            ExternalDiffOpenCall(
                wc: workingCopy,
                target: "a.swift",
                tool: tool,
                r1: Revision(1),
                r2: Revision(2)
            )
        ])
    }

    @MainActor
    func testOpenExternalDiffWithoutOpenerStoresUnavailableError() async {
        let viewModel = DiffViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            diffProvider: FakeDiffProvider(result: .success(""))
        )
        let tool = ExternalDiffToolConfiguration(
            name: "Kaleidoscope",
            executablePath: "/usr/local/bin/ksdiff",
            arguments: ["{left}", "{right}"]
        )

        await viewModel.openExternalDiff(target: "a.swift", tool: tool)

        XCTAssertEqual(viewModel.externalDiffState, .error("externalDiffUnavailable"))
    }

    @MainActor
    func testLoadAgainstBaseUsesDedicatedProvider() async {
        let provider = FakeDiffProvider(result: .success("+base\n"))
        let viewModel = DiffViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            diffProvider: provider
        )

        await viewModel.loadAgainstBase(target: "a.swift")
        let baseCalls = await provider.recordedAgainstBaseCalls()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(baseCalls, ["a.swift"])
    }

    @MainActor
    func testLoadBetweenPathsUsesOldAndNew() async {
        let provider = FakeDiffProvider(result: .success("-a\n+b\n"))
        let viewModel = DiffViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            diffProvider: provider
        )

        await viewModel.loadBetweenPaths(oldPath: "a.swift", newPath: "b.swift")
        let between = await provider.recordedBetweenPathCalls()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(between.map { "\($0.0)->\($0.1)" }, ["a.swift->b.swift"])
    }
}

private struct DiffCall: Equatable, Sendable {
    let wc: URL
    let target: String
    let r1: Revision?
    let r2: Revision?
}

private struct ExternalDiffOpenCall: Equatable, Sendable {
    let wc: URL
    let target: String
    let tool: ExternalDiffToolConfiguration
    let r1: Revision?
    let r2: Revision?
}

private actor FakeDiffProvider: DiffProviding {
    private let result: Result<String, Error>
    private var calls: [DiffCall] = []
    private var betweenPathCalls: [(String, String)] = []
    private var againstBaseCalls: [String] = []

    init(result: Result<String, Error>) {
        self.result = result
    }

    func recordedCalls() -> [DiffCall] {
        calls
    }

    func recordedBetweenPathCalls() -> [(String, String)] {
        betweenPathCalls
    }

    func recordedAgainstBaseCalls() -> [String] {
        againstBaseCalls
    }

    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        calls.append(DiffCall(wc: wc, target: target, r1: r1, r2: r2))
        return try result.get()
    }

    func diffBetweenPaths(wc: URL, oldPath: String, newPath: String) async throws -> String {
        betweenPathCalls.append((oldPath, newPath))
        return try result.get()
    }

    func diffAgainstBase(wc: URL, target: String) async throws -> String {
        againstBaseCalls.append(target)
        return try result.get()
    }
}

private actor FakeExternalDiffOpener: ExternalDiffOpening {
    private let result: Result<ExternalDiffLaunchResult, Error>
    private var calls: [ExternalDiffOpenCall] = []

    init(result: Result<ExternalDiffLaunchResult, Error>) {
        self.result = result
    }

    func recordedCalls() -> [ExternalDiffOpenCall] {
        calls
    }

    func open(
        wc: URL,
        target: String,
        tool: ExternalDiffToolConfiguration,
        r1: Revision?,
        r2: Revision?
    ) async throws -> ExternalDiffLaunchResult {
        calls.append(ExternalDiffOpenCall(wc: wc, target: target, tool: tool, r1: r1, r2: r2))
        return try result.get()
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacSvnCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
