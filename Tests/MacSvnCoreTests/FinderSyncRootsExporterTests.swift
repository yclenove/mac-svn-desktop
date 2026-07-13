import Foundation
import XCTest
@testable import MacSvnCore

final class FinderSyncContextMenuRootsExporterTests: XCTestCase {
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
}
