import XCTest
@testable import MacSvnCore

final class MergeInfoParserTests: XCTestCase {
    func testParsesMergeInfoEntriesAndRevisionRanges() throws {
        let value = """
        /branches/feature-a:2-4,7,9-10
        /branches/feature-b:5
        """

        let entries = try MergeInfoParser.parse(value)

        XCTAssertEqual(entries, [
            MergeInfoEntry(
                sourcePath: "/branches/feature-a",
                ranges: [
                    MergeInfoRevisionRange(start: Revision(2), end: Revision(4)),
                    MergeInfoRevisionRange(start: Revision(7), end: Revision(7)),
                    MergeInfoRevisionRange(start: Revision(9), end: Revision(10))
                ]
            ),
            MergeInfoEntry(
                sourcePath: "/branches/feature-b",
                ranges: [
                    MergeInfoRevisionRange(start: Revision(5), end: Revision(5))
                ]
            )
        ])
        XCTAssertEqual(entries[0].revisionCount, 6)
        XCTAssertEqual(entries[0].revisions, [
            Revision(2), Revision(3), Revision(4), Revision(7), Revision(9), Revision(10)
        ])
    }

    func testEmptyMergeInfoReturnsNoEntries() throws {
        XCTAssertEqual(try MergeInfoParser.parse(" \n\t"), [])
    }

    func testInvalidMergeInfoThrowsParseError() {
        XCTAssertThrowsError(try MergeInfoParser.parse("/branches/bad:not-a-revision")) { error in
            XCTAssertEqual(
                error as? SvnError,
                .parse(detail: "Invalid svn:mergeinfo revision range: not-a-revision")
            )
        }
    }

    func testMissingRevisionRangeThrowsParseError() {
        XCTAssertThrowsError(try MergeInfoParser.parse("/branches/bad:")) { error in
            XCTAssertEqual(
                error as? SvnError,
                .parse(detail: "Invalid svn:mergeinfo revision range: ")
            )
        }
    }
}
