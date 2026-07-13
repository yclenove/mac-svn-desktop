import Foundation
import XCTest
@testable import MacSvnCore

final class FinderSyncContextMenuSettingsTests: XCTestCase {
    func testDefaultsPreserveCurrentPromotedCommandsAndLegacyJSON() throws {
        let defaults = FinderSyncContextMenuSettings()
        XCTAssertEqual(
            defaults.promotedCommandIDs,
            [.update, .commit, .showLog, .diff, .revert, .resolved]
        )
        XCTAssertTrue(defaults.promoteLockForNeedsLock)
        XCTAssertFalse(defaults.hideMenusForUnversionedItems)
        XCTAssertTrue(defaults.excludedPaths.isEmpty)

        let decoded = try JSONDecoder().decode(
            FinderSyncContextMenuSettings.self,
            from: Data("{}".utf8)
        )
        XCTAssertEqual(decoded, defaults)
    }

    func testPromotedCommandsAreDeduplicatedAndLimitedToFinderCommands() {
        let settings = FinderSyncContextMenuSettings(
            promotedCommandIDs: [.copyMove, .copyMove, .logOpen, .getLock]
        )

        XCTAssertEqual(settings.promotedCommandIDs, [.copyMove, .getLock])
    }

    func testExcludedPathsUseDirectoryBoundariesAndNormalizeTilde() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let settings = FinderSyncContextMenuSettings(
            excludedPaths: ["~/Workspace/private", "/tmp/build"]
        )

        XCTAssertTrue(settings.excludes(path: home + "/Workspace/private/file.swift"))
        XCTAssertTrue(settings.excludes(path: "/tmp/build"))
        XCTAssertFalse(settings.excludes(path: "/tmp/build-output/file"))
        XCTAssertFalse(settings.excludes(path: "relative/path"))
    }
}
