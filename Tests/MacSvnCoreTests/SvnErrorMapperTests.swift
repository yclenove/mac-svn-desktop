import XCTest
@testable import MacSvnCore

final class SvnErrorMapperTests: XCTestCase {
    func testMapsAuthenticationErrors() {
        let error = SvnErrorMapper.map(exitCode: 1, stderr: "svn: E170001: Authentication failed")
        XCTAssertEqual(error, .authentication)
    }

    func testMapsOutOfDateErrors() {
        let error = SvnErrorMapper.map(exitCode: 1, stderr: "svn: E155011: File is out of date")
        XCTAssertEqual(error, .outOfDate)
    }

    func testMapsWorkingCopyLockedErrors() {
        let error = SvnErrorMapper.map(exitCode: 1, stderr: "svn: E155004: Working copy is locked")
        XCTAssertEqual(error, .wcLocked)
    }

    func testUnknownErrorPreservesCodeAndStderr() {
        let stderr = "svn: E199999: Strange failure"
        let error = SvnErrorMapper.map(exitCode: 7, stderr: stderr)
        XCTAssertEqual(error, .other(code: 199999, stderr: stderr))
    }
}
