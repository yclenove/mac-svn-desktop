import Foundation
import XCTest
@testable import MacSvnCore

final class VersionControlRemovalPolicyTests: XCTestCase {
    func testRejectsEmptyAndFilesystemRoot() {
        XCTAssertThrowsError(try VersionControlRemovalPolicy.validate(URL(fileURLWithPath: "/.svn")))
        XCTAssertThrowsError(try VersionControlRemovalPolicy.validate(URL(fileURLWithPath: "/")))
    }

    func testRejectsSVNMetadataDirectoryItself() {
        XCTAssertThrowsError(try VersionControlRemovalPolicy.validate(URL(fileURLWithPath: "/tmp/project/.svn")))
    }

    func testAcceptsAProjectDirectory() throws {
        let path = URL(fileURLWithPath: "/tmp/project")
        XCTAssertNoThrow(try VersionControlRemovalPolicy.validate(path))
    }
}
