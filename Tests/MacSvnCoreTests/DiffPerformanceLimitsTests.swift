import Foundation
import XCTest
@testable import MacSvnCore

final class DiffPerformanceLimitsTests: XCTestCase {
    func testShouldParseLineStructuresRespectsCharacterThreshold() {
        XCTAssertTrue(
            DiffPerformanceLimits.shouldParseLineStructures(
                diffCharacterCount: DiffPerformanceLimits.maxParseCharacterCount
            )
        )
        XCTAssertFalse(
            DiffPerformanceLimits.shouldParseLineStructures(
                diffCharacterCount: DiffPerformanceLimits.maxParseCharacterCount + 1
            )
        )
    }

    func testShouldUsePerLineSwiftUIBlocksEmbeddedAndOversized() {
        XCTAssertFalse(
            DiffPerformanceLimits.shouldUsePerLineSwiftUI(lineOrRowCount: 10, embedded: true)
        )
        XCTAssertFalse(
            DiffPerformanceLimits.shouldUsePerLineSwiftUI(lineOrRowCount: 0, embedded: false)
        )
        XCTAssertTrue(
            DiffPerformanceLimits.shouldUsePerLineSwiftUI(lineOrRowCount: 10, embedded: false)
        )
        XCTAssertTrue(
            DiffPerformanceLimits.shouldUsePerLineSwiftUI(
                lineOrRowCount: DiffPerformanceLimits.maxPerLineSwiftUIRowCount,
                embedded: false
            )
        )
        XCTAssertFalse(
            DiffPerformanceLimits.shouldUsePerLineSwiftUI(
                lineOrRowCount: DiffPerformanceLimits.maxPerLineSwiftUIRowCount + 1,
                embedded: false
            )
        )
    }

    func testTruncatedDisplayTextAppendsHintWhenOverLimit() {
        let raw = String(repeating: "a", count: DiffPerformanceLimits.maxDisplayCharacterCount + 50)
        let truncated = DiffPerformanceLimits.truncatedDisplayText(raw)
        XCTAssertTrue(truncated.hasPrefix(String(repeating: "a", count: DiffPerformanceLimits.maxDisplayCharacterCount)))
        XCTAssertTrue(truncated.contains("Diff 过长"))
        XCTAssertTrue(truncated.contains("外部 Diff"))
    }
}
