import XCTest
@testable import MacSvnCore

final class AuthArgumentsPasswordFromStdinTests: XCTestCase {
    func testNilCredentialProducesEmptyArgs() throws {
        let result = try AuthArguments.build(credential: nil)
        XCTAssertTrue(result.arguments.isEmpty)
        XCTAssertNil(result.stdin)
    }

    func testCredentialUsesPasswordFromStdinNotArgv() throws {
        let result = try AuthArguments.build(
            credential: Credential(username: "alice", password: "s3cret")
        )
        XCTAssertEqual(result.arguments, ["--username", "alice", "--password-from-stdin"])
        XCTAssertFalse(result.arguments.contains("s3cret"))
        XCTAssertEqual(result.stdin, Data("s3cret\n".utf8))
    }
}
