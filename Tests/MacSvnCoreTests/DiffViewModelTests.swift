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
}

private struct DiffCall: Equatable, Sendable {
    let wc: URL
    let target: String
    let r1: Revision?
    let r2: Revision?
}

private actor FakeDiffProvider: DiffProviding {
    private let result: Result<String, Error>
    private var calls: [DiffCall] = []

    init(result: Result<String, Error>) {
        self.result = result
    }

    func recordedCalls() -> [DiffCall] {
        calls
    }

    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        calls.append(DiffCall(wc: wc, target: target, r1: r1, r2: r2))
        return try result.get()
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacSvnCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
