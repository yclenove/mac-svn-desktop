import XCTest
@testable import MacSvnCore

final class AuthArgumentsTests: XCTestCase {
    func testBuildsUsernameAndPasswordFromStdinWithoutLeakingPasswordInArguments() throws {
        let credential = Credential(username: "yangchao", password: "secret-pass")
        let result = try AuthArguments.build(credential: credential)

        XCTAssertEqual(result.arguments, ["--username", "yangchao", "--password-from-stdin"])
        XCTAssertEqual(result.stdin, Data("secret-pass\n".utf8))
        XCTAssertFalse(result.arguments.contains("secret-pass"))
    }

    func testNilCredentialBuildsNoArgumentsAndNoStdin() throws {
        let result = try AuthArguments.build(credential: nil)

        XCTAssertEqual(result.arguments, [])
        XCTAssertNil(result.stdin)
    }
}
