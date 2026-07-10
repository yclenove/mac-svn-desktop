import XCTest
@testable import MacSvnCore

final class RenameValidationPolicyTests: XCTestCase {
    func testResolvesSameDirectoryDestination() {
        let result = RenameValidationPolicy.resolve(sourcePath: "src/main.txt", newName: "app.txt")
        guard case .success(let plan) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(plan.sourcePath, "src/main.txt")
        XCTAssertEqual(plan.destinationPath, "src/app.txt")
    }

    func testRootLevelRename() {
        let result = RenameValidationPolicy.resolve(sourcePath: "README.txt", newName: "LICENSE.txt")
        guard case .success(let plan) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(plan.destinationPath, "LICENSE.txt")
    }

    func testRejectsEmptyOrWhitespaceName() {
        XCTAssertEqual(
            RenameValidationPolicy.resolve(sourcePath: "a.txt", newName: "  "),
            .failure(.emptyNewName)
        )
    }

    func testRejectsSameBasename() {
        XCTAssertEqual(
            RenameValidationPolicy.resolve(sourcePath: "src/a.txt", newName: "a.txt"),
            .failure(.sameName)
        )
    }

    func testRejectsPathSeparatorsAndDotNames() {
        XCTAssertEqual(
            RenameValidationPolicy.resolve(sourcePath: "a.txt", newName: "b/c.txt"),
            .failure(.containsPathSeparator)
        )
        XCTAssertEqual(
            RenameValidationPolicy.resolve(sourcePath: "a.txt", newName: ".."),
            .failure(.invalidName)
        )
    }

    func testRejectsWhenDestinationAlreadyExists() {
        XCTAssertEqual(
            RenameValidationPolicy.resolve(
                sourcePath: "a.txt",
                newName: "b.txt",
                existingRelativePaths: ["b.txt", "c.txt"]
            ),
            .failure(.destinationExists("b.txt"))
        )
    }

    func testRejectsCaseInsensitiveCollisionWithOtherFile() {
        XCTAssertEqual(
            RenameValidationPolicy.resolve(
                sourcePath: "a.txt",
                newName: "FOO.txt",
                existingRelativePaths: ["a.txt", "Foo.txt"]
            ),
            .failure(.destinationExists("Foo.txt"))
        )
    }

    func testAllowsCaseOnlyRenameThroughValidation() {
        // 大小写冲突修复属 #46；此处仅允许进入 svn rename
        let result = RenameValidationPolicy.resolve(sourcePath: "Foo.txt", newName: "foo.txt")
        guard case .success(let plan) = result else {
            return XCTFail("expected success for case-only rename")
        }
        XCTAssertEqual(plan.destinationPath, "foo.txt")
    }
}
