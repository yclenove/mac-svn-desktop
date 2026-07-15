import Foundation
import XCTest
@testable import MacSvnApp

@MainActor
final class HumanCenteredCoreModesTests: XCTestCase {
    func testCoreModeWidthClassChangesAtDailyBaseline() {
        XCTAssertEqual(MacSvnCoreModeWidthClass.resolve(width: 1_179), .compact)
        XCTAssertEqual(MacSvnCoreModeWidthClass.resolve(width: 1_180), .regular)
    }

    func testLogFilterSummaryCountsEveryCombinableFilter() {
        XCTAssertEqual(
            MacSvnLogFilterSummary.activeCount(
                author: "alice",
                message: "fix",
                path: "Sources",
                stopOnCopy: true,
                offline: true
            ),
            5
        )
        XCTAssertEqual(
            MacSvnLogFilterSummary.activeCount(
                author: "  ",
                message: "",
                path: "",
                stopOnCopy: false,
                offline: false
            ),
            0
        )
    }

    func testCoreModeMetricsKeepMasterAndInspectorReadable() {
        XCTAssertEqual(MacSvnCoreModeMetrics.toolbarHeight, 48)
        XCTAssertGreaterThanOrEqual(MacSvnCoreModeMetrics.masterMinimumWidth, 320)
        XCTAssertGreaterThanOrEqual(MacSvnCoreModeMetrics.inspectorMinimumWidth, 360)
    }
}
