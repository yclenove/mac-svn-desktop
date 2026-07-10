import XCTest
@testable import MacSvnCore

final class LogChangedPathPolicyTests: XCTestCase {
    func testStripsWorkingCopyURLSuffixFromRepoPath() {
        let relative = LogChangedPathPolicy.workingCopyRelativePath(
            changedPath: "/trunk/Sources/a.swift",
            workingCopyURL: "file:///repo/trunk"
        )
        XCTAssertEqual(relative, "Sources/a.swift")
    }

    func testRelativePathPassthroughWhenNoLeadingMatch() {
        let relative = LogChangedPathPolicy.workingCopyRelativePath(
            changedPath: "Sources/a.swift",
            workingCopyURL: "file:///repo/trunk"
        )
        XCTAssertEqual(relative, "Sources/a.swift")
    }
}

final class LogContextActionPolicyTests: XCTestCase {
    func testCompareWithWorkingCopyIntent() {
        let intent = LogContextActionPolicy.intent(
            command: .logCompareWithWorkingCopy,
            changedPath: "/trunk/a.swift",
            revision: Revision(12),
            workingCopyURL: "file:///repo/trunk"
        )
        XCTAssertEqual(intent, .compareWithWorkingCopy(path: "a.swift", revision: Revision(12)))
    }

    func testBrowseBuildsURLUnderWorkingCopy() {
        let intent = LogContextActionPolicy.intent(
            command: .logBrowseRepository,
            changedPath: "/trunk/a.swift",
            revision: Revision(12),
            workingCopyURL: "file:///repo/trunk"
        )
        XCTAssertEqual(
            intent,
            .browseRepository(path: "a.swift", revision: Revision(12), repositoryURL: "file:///repo/trunk/a.swift")
        )
    }

    func testL03IsNotResolvedInT2Policy() {
        XCTAssertNil(
            LogContextActionPolicy.intent(
                command: .logCompareAndBlame,
                changedPath: "/trunk/a.swift",
                revision: Revision(1),
                workingCopyURL: "file:///repo/trunk"
            )
        )
    }
}
