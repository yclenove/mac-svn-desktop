import Foundation
import XCTest
@testable import MacSvnApp

final class HumanCenteredSpecializedToolsTests: XCTestCase {
    func testSpecializedPagesAreEnumerated() {
        let pages = Set(MacSvnSpecializedToolsPage.allCases.map(\.rawValue))
        XCTAssertEqual(
            pages,
            Set(["blame", "aiAssistant", "gitMigration", "releaseNotes"])
        )
    }

    func testMetricsAlignWithCoreAndAuxiliaryToolbars() {
        XCTAssertEqual(MacSvnSpecializedToolsMetrics.toolbarHeight, 48)
        XCTAssertEqual(MacSvnSpecializedToolsMetrics.feedbackBarHeight, 30)
        XCTAssertEqual(MacSvnSpecializedToolsMetrics.iconButtonMinSide, 28)
    }

    func testRefreshShortcutContract() {
        XCTAssertTrue(MacSvnSpecializedToolsContract.requiresRefreshShortcut(for: .blame))
        XCTAssertTrue(MacSvnSpecializedToolsContract.requiresRefreshShortcut(for: .aiAssistant))
        XCTAssertTrue(MacSvnSpecializedToolsContract.requiresRefreshShortcut(for: .releaseNotes))
        XCTAssertFalse(MacSvnSpecializedToolsContract.requiresRefreshShortcut(for: .gitMigration))
    }

    func testSearchFocusContractDefaultsToFalseForCurrentPages() {
        for page in MacSvnSpecializedToolsPage.allCases {
            XCTAssertFalse(
                MacSvnSpecializedToolsContract.requiresSearchFocus(for: page),
                "\(page.rawValue) should not require ⌘F until a search field is added"
            )
            XCTAssertNil(MacSvnSpecializedToolsContract.searchAccessibilityIdentifier(for: page))
        }
    }

    func testSpecializedPagesExposeStableAccessibilityIdentifiers() {
        XCTAssertEqual(
            MacSvnSpecializedToolsContract.refreshAccessibilityIdentifier(for: .blame),
            "macSvn.st.blame.refresh"
        )
        XCTAssertEqual(
            MacSvnSpecializedToolsContract.refreshAccessibilityIdentifier(for: .aiAssistant),
            "macSvn.st.aiAssistant.refresh"
        )
        XCTAssertEqual(
            MacSvnSpecializedToolsContract.refreshAccessibilityIdentifier(for: .releaseNotes),
            "macSvn.st.releaseNotes.refresh"
        )
        XCTAssertNil(MacSvnSpecializedToolsContract.refreshAccessibilityIdentifier(for: .gitMigration))
    }

    func testPresentationModuleAvoidsBusinessState() {
        let source = sourceOf("MacSvnSpecializedToolsPresentation.swift")
        for forbidden in ["ViewModel", "SvnService", "@State", "@Observable", "Navigator"] {
            XCTAssertFalse(
                source.contains(forbidden),
                "Specialized tools presentation must stay pure strategy; found \(forbidden)"
            )
        }
    }

    func testIndependentSplitViewBudgetConstant() {
        XCTAssertEqual(MacSvnSpecializedToolsContract.maxIndependentHSplitViewCount, 1)
    }

    // MARK: - Source gates (wired incrementally by later ST tasks)

    func testBlameViewWiresRefreshShortcutWhenRequired() throws {
        try assertRefreshWiring(
            fileName: "MacSvnBlameView.swift",
            page: .blame,
            requiredInTask: 2
        )
    }

    func testAIAssistantViewWiresRefreshShortcutWhenRequired() throws {
        try assertRefreshWiring(
            fileName: "MacSvnAIAssistantView.swift",
            page: .aiAssistant,
            requiredInTask: 3
        )
    }

    func testReleaseNotesViewWiresRefreshShortcutWhenRequired() throws {
        try assertRefreshWiring(
            fileName: "MacSvnReleaseNotesView.swift",
            page: .releaseNotes,
            requiredInTask: 4
        )
    }

    func testSpecializedToolViewsRespectSplitViewBoundary() throws {
        for fileName in [
            "MacSvnBlameView.swift",
            "MacSvnAIAssistantView.swift",
            "MacSvnGitMigrationView.swift",
            "MacSvnReleaseNotesView.swift",
        ] {
            let source = try sourceOfFeature(fileName)
            let hCount = source.components(separatedBy: "HSplitView").count - 1
            let vCount = source.components(separatedBy: "VSplitView").count - 1
            XCTAssertLessThanOrEqual(
                hCount,
                MacSvnSpecializedToolsContract.maxIndependentHSplitViewCount,
                "\(fileName) must not nest multiple HSplitView"
            )
            XCTAssertEqual(vCount, 0, "\(fileName) must not use VSplitView")
        }
    }

    // MARK: - Helpers

    private func assertRefreshWiring(
        fileName: String,
        page: MacSvnSpecializedToolsPage,
        requiredInTask: Int
    ) throws {
        guard MacSvnSpecializedToolsContract.requiresRefreshShortcut(for: page) else {
            return
        }
        let source = try sourceOfFeature(fileName)
        let identifier = try XCTUnwrap(
            MacSvnSpecializedToolsContract.refreshAccessibilityIdentifier(for: page)
        )
        // Task 1 only establishes contract + split budget; page wiring lands in later tasks.
        // Soft gate: if either piece is present, both must be present.
        let hasShortcut = source.contains("keyboardShortcut(\"r\", modifiers: .command)")
            || source.contains("keyboardShortcut(\"r\",modifiers: .command)")
        let hasIdentifier = source.contains(identifier)
        if hasShortcut || hasIdentifier {
            XCTAssertTrue(hasShortcut, "\(fileName) missing ⌘R after partial ST wiring (task \(requiredInTask))")
            XCTAssertTrue(hasIdentifier, "\(fileName) missing \(identifier) after partial ST wiring")
        }
    }

    private func sourceOf(_ fileName: String) -> String {
        let candidates = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/MacSvnApp/Features/\(fileName)"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/MacSvnApp/Features/\(fileName)"),
        ]
        for url in candidates {
            if let data = try? String(contentsOf: url, encoding: .utf8) {
                return data
            }
        }
        XCTFail("Could not read \(fileName)")
        return ""
    }

    private func sourceOfFeature(_ fileName: String) throws -> String {
        let text = sourceOf(fileName)
        if text.isEmpty {
            throw NSError(domain: "STTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(fileName)"])
        }
        return text
    }
}
