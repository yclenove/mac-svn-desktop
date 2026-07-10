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

    func testPegURLAppendsAtRevision() {
        XCTAssertEqual(
            LogChangedPathPolicy.pegURL(workingCopyURL: "file:///repo/trunk", revision: Revision(9)),
            "file:///repo/trunk@9"
        )
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

    func testCreateBranchTagUsesPegURL() {
        let intent = LogContextActionPolicy.intent(
            command: .logCreateBranchTagFromRevision,
            changedPath: "",
            revision: Revision(7),
            workingCopyURL: "file:///repo/trunk"
        )
        XCTAssertEqual(
            intent,
            .createBranchTag(sourcePegURL: "file:///repo/trunk@7", revision: Revision(7))
        )
    }

    func testUpdateToRevisionDefaultsToDotWhenPathEmpty() {
        let intent = LogContextActionPolicy.intent(
            command: .logUpdateItemToRevision,
            changedPath: "",
            revision: Revision(5),
            workingCopyURL: "file:///repo/trunk"
        )
        XCTAssertEqual(intent, .updateToRevision(path: ".", revision: Revision(5)))
    }

    func testReverseSingleRevisionRange() {
        XCTAssertEqual(
            LogContextActionPolicy.reverseSingleRevisionRange(Revision(10)),
            RevisionRange(start: Revision(10), end: Revision(9))
        )
        XCTAssertNil(LogContextActionPolicy.reverseSingleRevisionRange(Revision(0)))
    }

    func testRevertToRevisionRangeRequiresHeadStrictlyAfterTarget() {
        XCTAssertEqual(
            LogContextActionPolicy.revertToRevisionRange(head: Revision(20), target: Revision(12)),
            RevisionRange(start: Revision(20), end: Revision(12))
        )
        XCTAssertNil(LogContextActionPolicy.revertToRevisionRange(head: Revision(12), target: Revision(12)))
        XCTAssertNil(LogContextActionPolicy.revertToRevisionRange(head: Revision(5), target: Revision(12)))
    }

    func testStripPegRevisionKeepsUserAtHost() {
        XCTAssertEqual(
            LogContextActionPolicy.stripPegRevision(from: "svn+ssh://user@host/repo/trunk@42"),
            "svn+ssh://user@host/repo/trunk"
        )
        XCTAssertEqual(
            LogContextActionPolicy.stripPegRevision(from: "file:///repo/trunk@9"),
            "file:///repo/trunk"
        )
        XCTAssertEqual(
            LogContextActionPolicy.stripPegRevision(from: "svn+ssh://user@host/repo/trunk"),
            "svn+ssh://user@host/repo/trunk"
        )
    }
}
