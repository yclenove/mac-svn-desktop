import XCTest
@testable import MacSvnCore

final class FilenameCaseConflictRepairPolicyTests: XCTestCase {
    func testResolvesCaseOnlyRenameInSameDirectory() {
        let result = FilenameCaseConflictRepairPolicy.resolve(
            sourcePath: "src/Foo.txt",
            newName: "foo.txt",
            existingRelativePaths: ["src/Foo.txt"]
        )

        XCTAssertEqual(
            result,
            .success(FilenameCaseConflictRepairPlan(
                sourcePath: "src/Foo.txt",
                destinationPath: "src/foo.txt"
            ))
        )
    }

    func testRejectsRenameThatChangesMoreThanCase() {
        XCTAssertEqual(
            FilenameCaseConflictRepairPolicy.resolve(
                sourcePath: "Foo.txt",
                newName: "bar.txt"
            ),
            .failure(.notCaseOnlyRename)
        )
    }

    func testRejectsCaseOnlyRenameWhenAnotherPathOwnsDestination() {
        XCTAssertEqual(
            FilenameCaseConflictRepairPolicy.resolve(
                sourcePath: "Foo.txt",
                newName: "foo.txt",
                existingRelativePaths: ["Foo.txt", "foo.txt"]
            ),
            .failure(.destinationExists("foo.txt"))
        )
    }
}
