import Foundation
import XCTest
@testable import MacSvnApp

final class HumanCenteredGlobalExperienceTests: XCTestCase {
    func testKeyboardContractRequiresSearchFocusForSearchablePages() {
        XCTAssertTrue(MacSvnGlobalKeyboardContract.requiresSearchFocus(for: .changes))
        XCTAssertTrue(MacSvnGlobalKeyboardContract.requiresSearchFocus(for: .log))
        XCTAssertTrue(MacSvnGlobalKeyboardContract.requiresSearchFocus(for: .properties))
        XCTAssertTrue(MacSvnGlobalKeyboardContract.requiresSearchFocus(for: .locks))
        XCTAssertTrue(MacSvnGlobalKeyboardContract.requiresSearchFocus(for: .shelve))
        XCTAssertTrue(MacSvnGlobalKeyboardContract.requiresSearchFocus(for: .settings))
        XCTAssertFalse(MacSvnGlobalKeyboardContract.requiresSearchFocus(for: .branches))
        XCTAssertFalse(MacSvnGlobalKeyboardContract.requiresSearchFocus(for: .commit))
        XCTAssertFalse(MacSvnGlobalKeyboardContract.requiresSearchFocus(for: .diff))
        XCTAssertFalse(MacSvnGlobalKeyboardContract.requiresSearchFocus(for: .about))
    }

    func testKeyboardContractRequiresRefreshForRefreshablePages() {
        for page in MacSvnGlobalKeyboardPage.allCases {
            let expected = page != .about
            XCTAssertEqual(
                MacSvnGlobalKeyboardContract.requiresRefreshShortcut(for: page),
                expected,
                "\(page.rawValue) refresh shortcut expectation mismatch"
            )
        }
    }

    func testAccessibilityIdentifiersFollowMacSvnDotPrefix() {
        XCTAssertEqual(
            MacSvnGlobalKeyboardContract.searchAccessibilityIdentifier(for: .changes),
            "macSvn.changes.search"
        )
        XCTAssertEqual(
            MacSvnGlobalKeyboardContract.refreshAccessibilityIdentifier(for: .changes),
            "macSvn.changes.refresh"
        )
        XCTAssertEqual(
            MacSvnGlobalKeyboardContract.refreshAccessibilityIdentifier(for: .log),
            "macSvn.log.refresh"
        )
        XCTAssertNil(MacSvnGlobalKeyboardContract.searchAccessibilityIdentifier(for: .branches))
        XCTAssertNil(MacSvnGlobalKeyboardContract.refreshAccessibilityIdentifier(for: .about))
        XCTAssertNil(MacSvnGlobalKeyboardContract.searchAccessibilityIdentifier(for: .about))
    }

    func testMotionPolicyDisablesAnimationWhenReduceMotionIsActive() {
        XCTAssertFalse(
            MacSvnMotionPolicy.shouldAnimate(accessibilityReduceMotion: false, override: true)
        )
        XCTAssertFalse(
            MacSvnMotionPolicy.shouldAnimate(accessibilityReduceMotion: true, override: nil)
        )
        // override false forces animation even if system reduce motion is on
        XCTAssertTrue(
            MacSvnMotionPolicy.shouldAnimate(accessibilityReduceMotion: true, override: false)
        )
        XCTAssertTrue(
            MacSvnMotionPolicy.shouldAnimate(accessibilityReduceMotion: false, override: nil)
        )
        XCTAssertTrue(
            MacSvnMotionPolicy.shouldAnimate(accessibilityReduceMotion: false, override: false)
        )
    }

    func testMotionPolicyRunSkipsAnimationWhenReduceMotionOverrideIsTrue() {
        var ran = false
        MacSvnMotionPolicy.run(
            accessibilityReduceMotion: false,
            override: true
        ) {
            ran = true
        }
        XCTAssertTrue(ran)
    }

    // MARK: - Source guards: Changes

    func testChangesViewWiresSearchFocusAndRefreshShortcuts() throws {
        let source = try Self.readFeatureSource(named: "MacSvnChangesView.swift")
        XCTAssertTrue(source.contains("@FocusState"), "Changes needs FocusState for ⌘F")
        XCTAssertTrue(
            source.contains("keyboardShortcut(\"f\", modifiers: .command)"),
            "Changes must wire ⌘F"
        )
        XCTAssertTrue(
            source.contains("keyboardShortcut(\"r\", modifiers: .command)"),
            "Changes must wire ⌘R"
        )
        XCTAssertTrue(
            source.contains("macSvn.changes.search"),
            "Changes search needs global a11y id"
        )
        XCTAssertTrue(
            source.contains("macSvn.changes.refresh"),
            "Changes refresh needs global a11y id"
        )
    }

    // MARK: - Source guards: core / auxiliary refresh pages

    func testRefreshablePagesWireCommandRAndIdentifier() throws {
        let pages: [(file: String, page: MacSvnGlobalKeyboardPage)] = [
            ("MacSvnLogView.swift", .log),
            ("MacSvnRepoBrowserView.swift", .repoBrowser),
            ("MacSvnBranchesView.swift", .branches),
            ("MacSvnConflictWorkspaceView.swift", .conflicts),
            ("MacSvnDiffView.swift", .diff),
            ("MacSvnCommitView.swift", .commit),
            ("MacSvnPropertiesView.swift", .properties),
            ("MacSvnLocksView.swift", .locks),
            ("MacSvnShelveView.swift", .shelve),
            ("MacSvnSettingsView.swift", .settings),
        ]

        for item in pages {
            let source = try Self.readFeatureSource(named: item.file)
            XCTAssertTrue(
                MacSvnGlobalKeyboardContract.requiresRefreshShortcut(for: item.page)
            )
            XCTAssertTrue(
                source.contains("keyboardShortcut(\"r\", modifiers: .command)"),
                "\(item.file) must wire ⌘R"
            )
            let expectedID = try XCTUnwrap(
                MacSvnGlobalKeyboardContract.refreshAccessibilityIdentifier(for: item.page)
            )
            XCTAssertTrue(
                source.contains(expectedID),
                "\(item.file) must expose \(expectedID)"
            )
        }
    }

    func testSearchablePagesWireCommandF() throws {
        let pages: [(file: String, page: MacSvnGlobalKeyboardPage)] = [
            ("MacSvnChangesView.swift", .changes),
            ("MacSvnLogView.swift", .log),
            ("MacSvnPropertiesView.swift", .properties),
            ("MacSvnLocksView.swift", .locks),
            ("MacSvnShelveView.swift", .shelve),
            ("MacSvnSettingsView.swift", .settings),
        ]

        for item in pages {
            let source = try Self.readFeatureSource(named: item.file)
            XCTAssertTrue(MacSvnGlobalKeyboardContract.requiresSearchFocus(for: item.page))
            XCTAssertTrue(
                source.contains("keyboardShortcut(\"f\", modifiers: .command)"),
                "\(item.file) must wire ⌘F"
            )
            if let expectedID = MacSvnGlobalKeyboardContract.searchAccessibilityIdentifier(for: item.page) {
                // Changes and U7 pages gradually adopt ids; require for all searchable.
                XCTAssertTrue(
                    source.contains(expectedID),
                    "\(item.file) must expose \(expectedID)"
                )
            }
        }
    }

    func testCommitViewUsesMotionPolicy() throws {
        let source = try Self.readFeatureSource(named: "MacSvnCommitView.swift")
        XCTAssertTrue(
            source.contains("MacSvnMotionPolicy"),
            "Commit inspector animation must use MacSvnMotionPolicy"
        )
    }

    func testGlobalExperiencePresentationAvoidsBusinessState() throws {
        let source = try Self.readFeatureSource(named: "MacSvnGlobalExperiencePresentation.swift")
        XCTAssertFalse(source.contains("ViewModel"))
        XCTAssertFalse(source.contains("SvnService"))
        XCTAssertTrue(source.contains("MacSvnGlobalKeyboardContract"))
        XCTAssertTrue(source.contains("MacSvnMotionPolicy"))
    }

    // MARK: - Helpers

    private static func readFeatureSource(named name: String) throws -> String {
        let url = try featureSourceURL(named: name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func featureSourceURL(named name: String) throws -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        var directory = thisFile.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = directory
                .appendingPathComponent("Sources/MacSvnApp/Features", isDirectory: true)
                .appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory = directory.deletingLastPathComponent()
        }
        XCTFail("Could not locate Sources/MacSvnApp/Features/\(name)")
        throw NSError(domain: "HumanCenteredGlobalExperienceTests", code: 1)
    }
}
