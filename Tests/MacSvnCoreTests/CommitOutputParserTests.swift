import XCTest
@testable import MacSvnCore

final class CommitOutputParserTests: XCTestCase {
    func testParsesCommittedRevision() throws {
        let revision = try CommitOutputParser.parseRevision(from: "Sending file\nCommitted revision 42.\n")
        XCTAssertEqual(revision, Revision(42))
    }

    func testThrowsParseErrorWhenRevisionIsMissing() {
        XCTAssertThrowsError(try CommitOutputParser.parseRevision(from: "No revision here")) { error in
            XCTAssertEqual(error as? SvnError, .parse(detail: "Unable to find committed revision in svn commit output."))
        }
    }
}
