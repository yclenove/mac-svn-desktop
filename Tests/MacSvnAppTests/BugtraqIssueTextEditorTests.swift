import AppKit
import XCTest
@testable import MacSvnApp

final class BugtraqIssueTextEditorTests: XCTestCase {
    func testSingleRegexHighlightsCaptureGroupsOnly() {
        let text = "Fixes issue #42 and issue #7"

        let ranges = BugtraqIssueHighlighting.ranges(
            for: ["[Ii]ssue #?(\\d+)"],
            in: text
        )

        XCTAssertEqual(ranges.map { (text as NSString).substring(with: $0) }, ["42", "7"])
    }

    func testTwoStageRegexHighlightsInnerCaptureGroups() {
        let text = "Refs: #23, #24"

        let ranges = BugtraqIssueHighlighting.ranges(
            for: ["Refs:.*", "#(\\d+)"],
            in: text
        )

        XCTAssertEqual(ranges.map { (text as NSString).substring(with: $0) }, ["23", "24"])
    }
}
