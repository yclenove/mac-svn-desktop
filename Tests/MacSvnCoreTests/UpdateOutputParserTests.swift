import XCTest
@testable import MacSvnCore

final class UpdateOutputParserTests: XCTestCase {
    func testParsesActionCountsAndRevision() throws {
        let output = """
        A    new.txt
        U    changed.txt
        D    removed.txt
        C    conflicted.txt
        G    merged.txt
        Updated to revision 88.
        """

        let summary = try UpdateOutputParser.parse(output)

        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(summary.updated, 1)
        XCTAssertEqual(summary.deleted, 1)
        XCTAssertEqual(summary.conflicted, 1)
        XCTAssertEqual(summary.merged, 1)
        XCTAssertEqual(summary.revision, Revision(88))
    }

    func testIgnoresUnknownLines() throws {
        let output = """
        Random progress line
        U    known.txt
        At revision 9.
        """

        let summary = try UpdateOutputParser.parse(output)

        XCTAssertEqual(summary.updated, 1)
        XCTAssertEqual(summary.revision, Revision(9))
    }
}
