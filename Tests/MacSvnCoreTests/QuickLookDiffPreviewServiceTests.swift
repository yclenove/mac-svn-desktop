import Foundation
import XCTest
@testable import MacSvnCore

final class QuickLookDiffPreviewServiceTests: XCTestCase {
    func testPreviewLoadsRelativeBaselineDiffAndClassifiesLines() async throws {
        let workingCopy = try makeTemporaryDirectory()
        let sourceDirectory = workingCopy.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let fileURL = sourceDirectory.appendingPathComponent("App.swift")
        try "let value = 2\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let diff = """
        Index: Sources/App.swift
        ===================================================================
        --- Sources/App.swift\t(revision 4)
        +++ Sources/App.swift\t(working copy)
        @@ -1,1 +1,1 @@
        -let value = 1
        +let value = 2
        """
        let provider = FakeQuickLookDiffProvider(result: .success(diff))
        let service = QuickLookDiffPreviewService(workingCopy: workingCopy, diffProvider: provider)

        let result = await service.preview(fileURL: fileURL)
        let calls = await provider.recordedCalls()

        guard case .preview(let preview) = result else {
            return XCTFail("Expected preview result, got \(result)")
        }
        XCTAssertEqual(preview.workingCopy, workingCopy.standardizedFileURL)
        XCTAssertEqual(preview.fileURL, fileURL.standardizedFileURL)
        XCTAssertEqual(preview.target, "Sources/App.swift")
        XCTAssertEqual(preview.diffText, diff)
        XCTAssertEqual(preview.lines.map(\.kind), [
            .metadata, .metadata, .metadata, .metadata,
            .hunk, .deletion, .addition
        ])
        XCTAssertEqual(calls, [
            QuickLookDiffCall(wc: workingCopy.standardizedFileURL, target: "Sources/App.swift", r1: nil, r2: nil)
        ])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct QuickLookDiffCall: Equatable, Sendable {
    let wc: URL
    let target: String
    let r1: Revision?
    let r2: Revision?
}

private actor FakeQuickLookDiffProvider: DiffProviding {
    private let result: Result<String, Error>
    private var calls: [QuickLookDiffCall] = []

    init(result: Result<String, Error>) {
        self.result = result
    }

    func recordedCalls() -> [QuickLookDiffCall] {
        calls
    }

    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        calls.append(QuickLookDiffCall(wc: wc, target: target, r1: r1, r2: r2))
        return try result.get()
    }
}
