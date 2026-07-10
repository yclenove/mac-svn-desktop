import XCTest
@testable import MacSvnCore

final class FinderSyncDeepLinkBuilderTests: XCTestCase {
    func testBuildsMacsvnURLsForMenuActions() throws {
        let builder = FinderSyncDeepLinkBuilder()
        let path = "/Users/me/wc/Sources/App.swift"

        let open = try XCTUnwrap(builder.url(for: .update, path: path))
        XCTAssertEqual(open.scheme, "macsvn")
        XCTAssertEqual(open.host, "open")
        XCTAssertEqual(URLComponents(url: open, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "path" }?.value, path)
        XCTAssertEqual(URLComponents(url: open, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "action" }?.value, "update")

        let diff = try XCTUnwrap(builder.url(for: .diff, path: path))
        XCTAssertEqual(diff.host, "diff")

        let log = try XCTUnwrap(builder.url(for: .log, path: path))
        XCTAssertEqual(log.host, "log")

        let commit = try XCTUnwrap(builder.url(for: .commit, path: path))
        XCTAssertEqual(commit.host, "open")
        XCTAssertEqual(URLComponents(url: commit, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "action" }?.value, "commit")
    }
}

final class FinderSyncRootsExporterTests: XCTestCase {
    func testExportAndLoadValidRoots() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("finder-roots-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let records = [
            WorkingCopyRecord(
                id: UUID(),
                name: "a",
                localPath: "/tmp/wc-a",
                repoURL: "file:///repo",
                username: nil,
                addedAt: Date(timeIntervalSince1970: 1),
                lastOpenedAt: Date(timeIntervalSince1970: 1),
                isValid: true,
                revision: Revision(1)
            ),
            WorkingCopyRecord(
                id: UUID(),
                name: "b",
                localPath: "/tmp/wc-b",
                repoURL: "file:///repo",
                username: nil,
                addedAt: Date(timeIntervalSince1970: 1),
                lastOpenedAt: Date(timeIntervalSince1970: 1),
                isValid: false,
                revision: nil
            ),
        ]

        let fileURL = FinderSyncRootsExporter.fileURL(in: directory)
        try FinderSyncRootsExporter.export(records: records, to: fileURL)
        let loaded = try FinderSyncRootsExporter.load(from: fileURL)
        XCTAssertEqual(loaded, ["/tmp/wc-a"])
    }
}
