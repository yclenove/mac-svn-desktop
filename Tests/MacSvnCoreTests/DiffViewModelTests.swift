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
