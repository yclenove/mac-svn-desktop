import Foundation
import XCTest
@testable import MacSvnCore

final class PatchPathPolicyTests: XCTestCase {
    func testRejectsEmptySelection() {
        XCTAssertThrowsError(try PatchPathPolicy.validate([]))
        XCTAssertThrowsError(try PatchPathPolicy.validate(["", "  "]))
    }

    func testTrimsAndPreservesSelectedPathOrder() throws {
        XCTAssertEqual(try PatchPathPolicy.validate([" README.txt ", "src/main.swift"]), ["README.txt", "src/main.swift"])
    }
}
