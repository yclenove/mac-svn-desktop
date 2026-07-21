import XCTest
@testable import MacSvnCore

final class FinderSyncOverlaySettingsTests: XCTestCase {
    func testEmptyIncludesAllowAllPathsAndExcludesWin() {
        let settings = FinderSyncOverlaySettings(
            includedPaths: [],
            excludedPaths: ["/Users/yangchao/Workspace/ignored"]
        )

        XCTAssertTrue(settings.allows(path: "/Users/yangchao/Workspace/repo/file.swift"))
        XCTAssertFalse(settings.allows(path: "/Users/yangchao/Workspace/ignored/file.swift"))
        XCTAssertTrue(settings.allows(path: "/Users/yangchao/Workspace/ignored-sibling/file.swift"))
    }

    func testIncludesRestrictPathsToConfiguredSubtrees() {
        let settings = FinderSyncOverlaySettings(
            includedPaths: ["/Volumes/Dev/Project/src"],
            excludedPaths: []
        )

        XCTAssertTrue(settings.allows(path: "/Volumes/Dev/Project/src/App.swift"))
        XCTAssertTrue(settings.allows(path: "/Volumes/Dev/Project/src"))
        XCTAssertFalse(settings.allows(path: "/Volumes/Dev/Project/tests/AppTests.swift"))
    }

    func testExcludedPathWinsWhenItIsInsideIncludedSubtree() {
        let settings = FinderSyncOverlaySettings(
            includedPaths: ["/Volumes/Dev/Project"],
            excludedPaths: ["/Volumes/Dev/Project/.build"]
        )

        XCTAssertFalse(settings.allows(path: "/Volumes/Dev/Project/.build/debug/App"))
        XCTAssertTrue(settings.allows(path: "/Volumes/Dev/Project/Sources/App.swift"))
    }

    func testMonitoredDirectoriesUseIncludedSubtreesWithinWorkingCopies() {
        let settings = FinderSyncOverlaySettings(
            includedPaths: ["/Volumes/Dev/Project/Sources", "/tmp/outside"],
            excludedPaths: []
        )

        XCTAssertEqual(
            settings.monitoredDirectories(for: ["/Volumes/Dev/Project"]),
            ["/Volumes/Dev/Project/Sources"]
        )
    }

    func testMonitoredDirectoriesKeepRootsWhenIncludesAreEmptyAndDropExcludedRoots() {
        let settings = FinderSyncOverlaySettings(
            excludedPaths: ["/Volumes/Dev/Excluded"]
        )

        XCTAssertEqual(
            settings.monitoredDirectories(for: ["/Volumes/Dev/Project", "/Volumes/Dev/Excluded"]),
            ["/Volumes/Dev/Project"]
        )
    }

    func testEmptyEnabledBadgesDecodeToAllBadgesForLegacyConfiguration() throws {
        let data = Data(#"{"includedPaths":[],"excludedPaths":[]}"#.utf8)

        let decoded = try JSONDecoder().decode(FinderSyncOverlaySettings.self, from: data)

        XCTAssertEqual(decoded.enabledBadges, Set(FinderSyncBadge.allCases))
    }
}
