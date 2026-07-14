import Foundation
import XCTest
@testable import MacSvnCore

final class FinderSyncContextMenuRootsExporterTests: XCTestCase {
    func testExtensionContainerSupportDirectoryUsesFinderBundleContainer() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

        let support = FinderSyncRootsExporter.extensionContainerSupportDirectory(
            homeDirectory: home
        )

        XCTAssertEqual(
            support.path,
            "/Users/tester/Library/Containers/dev.yclenove.svnstudio.FinderSync/"
                + "Data/Library/Application Support/SVNStudio"
        )
    }

    func testLegacyConfigurationDefaultsContextMenuSettings() throws {
        let data = Data(#"{"version":3,"roots":["/tmp/wc"],"cacheMode":"shell","overlaySettings":{}}"#.utf8)

        let decoded = try JSONDecoder().decode(FinderSyncRootsFile.self, from: data)

        XCTAssertEqual(decoded.contextMenuSettings, FinderSyncContextMenuSettings())
    }

    func testExportPersistsContextMenuSettingsAndVersionFour() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("finder-sync-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("finder-sync-roots.json")
        let menuSettings = FinderSyncContextMenuSettings(
            promotedCommandIDs: [.copyMove, .update],
            promoteLockForNeedsLock: false,
            hideMenusForUnversionedItems: true,
            excludedPaths: ["/tmp/wc/vendor"]
        )

        try FinderSyncRootsExporter.export(
            records: [],
            cacheMode: .shell,
            overlaySettings: FinderSyncOverlaySettings(enabledBadges: [.modified]),
            contextMenuSettings: menuSettings,
            to: fileURL
        )

        let loaded = try FinderSyncRootsExporter.loadConfiguration(from: fileURL)
        XCTAssertEqual(loaded.version, 4)
        XCTAssertEqual(loaded.contextMenuSettings, menuSettings)
    }

    func testExportWritesIdenticalConfigurationToEveryDestination() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("finder-sync-mirror-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let primary = root.appendingPathComponent("primary/finder-sync-roots.json")
        let mirror = root.appendingPathComponent("extension/finder-sync-roots.json")
        let record = WorkingCopyRecord(
            id: UUID(),
            name: "wc",
            localPath: "/tmp/wc",
            repoURL: "file:///tmp/repo/trunk",
            username: nil,
            addedAt: Date(timeIntervalSince1970: 1),
            lastOpenedAt: Date(timeIntervalSince1970: 1),
            isValid: true,
            revision: Revision(1)
        )

        try FinderSyncRootsExporter.export(
            records: [record],
            cacheMode: .shell,
            overlaySettings: FinderSyncOverlaySettings(enabledBadges: [.normal, .modified]),
            contextMenuSettings: FinderSyncContextMenuSettings(
                promotedCommandIDs: [.update, .commit]
            ),
            to: [primary, mirror]
        )

        XCTAssertEqual(try Data(contentsOf: primary), try Data(contentsOf: mirror))
        XCTAssertEqual(try FinderSyncRootsExporter.load(from: mirror), ["/tmp/wc"])
    }
}
