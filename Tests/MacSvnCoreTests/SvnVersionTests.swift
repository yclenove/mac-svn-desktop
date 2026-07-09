import XCTest
@testable import MacSvnCore

final class SvnVersionTests: XCTestCase {
    func testParsesQuietVersionOutput() throws {
        XCTAssertEqual(try SvnVersion.parse("1.14.5\n"), SvnVersion(major: 1, minor: 14, patch: 5))
    }

    func testRejectsInvalidVersionOutput() {
        XCTAssertThrowsError(try SvnVersion.parse("not-a-version")) { error in
            XCTAssertEqual(error as? SvnError, .parse(detail: "Unable to parse svn version: not-a-version"))
        }
    }
}
