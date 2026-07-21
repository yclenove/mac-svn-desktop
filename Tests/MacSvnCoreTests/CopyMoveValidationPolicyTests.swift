import XCTest
@testable import MacSvnCore

final class CopyMoveValidationPolicyTests: XCTestCase {
    func testMoveToOtherDirectory() {
        let result = CopyMoveValidationPolicy.resolve(
            kind: .move,
            sourcePath: "src/a.txt",
            destinationPath: "lib/a.txt",
            existingRelativePaths: ["src/a.txt"]
        )
        guard case .success(let plan) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(plan.kind, .move)
        XCTAssertEqual(plan.sourcePath, "src/a.txt")
        XCTAssertEqual(plan.destinationPath, "lib/a.txt")
    }

    func testNormalizesSlashesAndRejectsAbsolute() {
        let ok = CopyMoveValidationPolicy.resolve(
            kind: .copy,
            sourcePath: "a.txt",
            destinationPath: " ./dir/b.txt ",
            existingRelativePaths: ["a.txt"]
        )
        guard case .success(let plan) = ok else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(plan.destinationPath, "dir/b.txt")

        XCTAssertEqual(
            CopyMoveValidationPolicy.resolve(
                kind: .copy,
                sourcePath: "a.txt",
                destinationPath: "/tmp/a.txt",
                existingRelativePaths: ["a.txt"]
            ),
            .failure(.absoluteDestination)
        )
    }

    func testRejectsEmptySameAndParentEscape() {
        XCTAssertEqual(
            CopyMoveValidationPolicy.resolve(
                kind: .move,
                sourcePath: "a.txt",
                destinationPath: "  ",
                existingRelativePaths: ["a.txt"]
            ),
            .failure(.emptyDestination)
        )
        XCTAssertEqual(
            CopyMoveValidationPolicy.resolve(
                kind: .move,
                sourcePath: "a.txt",
                destinationPath: "a.txt",
                existingRelativePaths: ["a.txt"]
            ),
            .failure(.samePath)
        )
        XCTAssertEqual(
            CopyMoveValidationPolicy.resolve(
                kind: .move,
                sourcePath: "src/a.txt",
                destinationPath: "../outside.txt",
                existingRelativePaths: ["src/a.txt"]
            ),
            .failure(.escapesWorkingCopy)
        )
    }

    func testRejectsExistingDestinationCaseInsensitive() {
        XCTAssertEqual(
            CopyMoveValidationPolicy.resolve(
                kind: .copy,
                sourcePath: "a.txt",
                destinationPath: "Dir/B.txt",
                existingRelativePaths: ["a.txt", "dir/b.txt"]
            ),
            .failure(.destinationExists("dir/b.txt"))
        )
    }
}
