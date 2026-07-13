import XCTest
@testable import MacSvnCore

final class FinderSyncDeepLinkBuilderTests: XCTestCase {
    func testBuildsMacsvnURLsForMenuActions() throws {
        let builder = FinderSyncDeepLinkBuilder()
        let path = "/Users/me/wc/Sources/App.swift"

        let open = try XCTUnwrap(builder.url(for: .update, path: path))
        XCTAssertEqual(open.scheme, ProductBranding.urlScheme)
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

    func testBuildsCommandURLForFinderExtendedMenu() throws {
        let builder = FinderSyncDeepLinkBuilder()
        let url = try XCTUnwrap(builder.commandURL(for: .deleteKeepLocal, path: "/Users/me/repo/file.txt"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.host, "command")
        XCTAssertEqual(components.queryItems?.first { $0.name == "path" }?.value, "/Users/me/repo/file.txt")
        XCTAssertEqual(components.queryItems?.first { $0.name == "command" }?.value, SvnCommandID.deleteKeepLocal.rawValue)
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

    func testExportsAndLoadsExplicitCacheMode() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = FinderSyncRootsExporter.fileURL(in: directory)

        try FinderSyncRootsExporter.export(
            records: [record(path: "/tmp/wc-a")],
            cacheMode: .shell,
            to: fileURL
        )

        let configuration = try FinderSyncRootsExporter.loadConfiguration(from: fileURL)
        XCTAssertEqual(configuration.roots, ["/tmp/wc-a"])
        XCTAssertEqual(configuration.cacheMode, .shell)
    }

    func testLegacyRootsFileDefaultsToDefaultCache() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = FinderSyncRootsExporter.fileURL(in: directory)
        try Data(#"{"version":1,"roots":["/tmp/wc"]}"#.utf8).write(to: fileURL)

        let configuration = try FinderSyncRootsExporter.loadConfiguration(from: fileURL)

        XCTAssertEqual(configuration.cacheMode, .defaultCache)
        XCTAssertEqual(configuration.roots, ["/tmp/wc"])
    }

    func testRootOnlyExportPreservesExistingCacheMode() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = FinderSyncRootsExporter.fileURL(in: directory)
        try FinderSyncRootsExporter.export(
            records: [record(path: "/tmp/old")],
            cacheMode: .shell,
            to: fileURL
        )

        try FinderSyncRootsExporter.export(records: [record(path: "/tmp/new")], to: fileURL)

        let configuration = try FinderSyncRootsExporter.loadConfiguration(from: fileURL)
        XCTAssertEqual(configuration.cacheMode, .shell)
        XCTAssertEqual(configuration.roots, ["/tmp/new"])
    }

    func testExportAndLoadPreservesOverlaySettings() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = FinderSyncRootsExporter.fileURL(in: directory)
        let overlaySettings = FinderSyncOverlaySettings(
            includedPaths: ["/tmp/include"],
            excludedPaths: ["/tmp/include/.build"],
            enabledBadges: [.modified, .normal]
        )

        try FinderSyncRootsExporter.export(
            records: [record(path: "/tmp/wc-a")],
            cacheMode: .shell,
            overlaySettings: overlaySettings,
            to: fileURL
        )

        let configuration = try FinderSyncRootsExporter.loadConfiguration(from: fileURL)
        XCTAssertEqual(configuration.overlaySettings, overlaySettings)
    }

    func testRootOnlyExportPreservesExistingOverlaySettings() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = FinderSyncRootsExporter.fileURL(in: directory)
        let overlaySettings = FinderSyncOverlaySettings(includedPaths: ["/tmp/include"])
        try FinderSyncRootsExporter.export(
            records: [record(path: "/tmp/old")],
            cacheMode: .defaultCache,
            overlaySettings: overlaySettings,
            to: fileURL
        )

        try FinderSyncRootsExporter.export(records: [record(path: "/tmp/new")], to: fileURL)

        let configuration = try FinderSyncRootsExporter.loadConfiguration(from: fileURL)
        XCTAssertEqual(configuration.overlaySettings, overlaySettings)
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("finder-roots-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func record(path: String) -> WorkingCopyRecord {
        WorkingCopyRecord(
            id: UUID(),
            name: "wc",
            localPath: path,
            repoURL: "file:///repo",
            username: nil,
            addedAt: Date(timeIntervalSince1970: 1),
            lastOpenedAt: Date(timeIntervalSince1970: 1),
            isValid: true,
            revision: Revision(1)
        )
    }
}
