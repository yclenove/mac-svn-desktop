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

    func testPreviewRejectsOutsideWorkingCopyDirectoriesAndMissingFilesWithoutCallingDiff() async throws {
        let workingCopy = try makeTemporaryDirectory()
        let outsideFile = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).swift")
        try "outside\n".write(to: outsideFile, atomically: true, encoding: .utf8)
        let directoryURL = workingCopy.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let missingFile = workingCopy.appendingPathComponent("Missing.swift")
        let provider = FakeQuickLookDiffProvider(result: .success(""))
        let service = QuickLookDiffPreviewService(workingCopy: workingCopy, diffProvider: provider)

        let outside = await service.preview(fileURL: outsideFile)
        let directory = await service.preview(fileURL: directoryURL)
        let missing = await service.preview(fileURL: missingFile)
        let calls = await provider.recordedCalls()

        XCTAssertEqual(outside, .unsupported(.outsideWorkingCopy))
        XCTAssertEqual(directory, .unsupported(.directory))
        XCTAssertEqual(missing, .unsupported(.missing))
        XCTAssertEqual(calls, [])
    }

    func testPreviewMapsBinaryDiffToUnsupportedWithLocalFileDetails() async throws {
        let workingCopy = try makeTemporaryDirectory()
        let fileURL = workingCopy.appendingPathComponent("image.bin")
        try Data([1, 2, 3, 4, 5]).write(to: fileURL)
        let provider = FakeQuickLookDiffProvider(result: .success("Cannot display: file marked as a binary type.\n"))
        let service = QuickLookDiffPreviewService(workingCopy: workingCopy, diffProvider: provider)

        let result = await service.preview(fileURL: fileURL)

        guard case .unsupported(.binary(let details)) = result else {
            return XCTFail("Expected binary unsupported result, got \(result)")
        }
        XCTAssertEqual(details?.size, 5)
        XCTAssertNotNil(details?.modifiedAt)
    }

    func testPreviewMapsProviderFailureToError() async throws {
        let workingCopy = try makeTemporaryDirectory()
        let fileURL = workingCopy.appendingPathComponent("App.swift")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let provider = FakeQuickLookDiffProvider(result: .failure(SvnError.network(detail: "offline")))
        let service = QuickLookDiffPreviewService(workingCopy: workingCopy, diffProvider: provider)

        let result = await service.preview(fileURL: fileURL)

        XCTAssertEqual(result, .error(String(describing: SvnError.network(detail: "offline"))))
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
