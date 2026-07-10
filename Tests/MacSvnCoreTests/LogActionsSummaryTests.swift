import XCTest
@testable import MacSvnCore

final class LogActionsSummaryTests: XCTestCase {
    func testEmptyPathsYieldEmptyActions() {
        XCTAssertEqual(LogActionsSummary.symbols(for: []), "")
    }

    func testAggregatesUniqueActionsInMADRorder() {
        let paths = [
            ChangedPath(path: "/a", action: .deleted, kind: nil, copyFromPath: nil, copyFromRevision: nil),
            ChangedPath(path: "/b", action: .added, kind: nil, copyFromPath: nil, copyFromRevision: nil),
            ChangedPath(path: "/c", action: .modified, kind: nil, copyFromPath: nil, copyFromRevision: nil),
            ChangedPath(path: "/d", action: .replaced, kind: nil, copyFromPath: nil, copyFromRevision: nil),
            ChangedPath(path: "/e", action: .added, kind: nil, copyFromPath: nil, copyFromRevision: nil),
        ]
        XCTAssertEqual(LogActionsSummary.symbols(for: paths), "MADR")
    }
}
