import XCTest
@testable import MacSvnCore

final class GitCommandBuilderTests: XCTestCase {
    func testInitRepositoryUsesInit() {
        XCTAssertEqual(GitCommandBuilder.initRepository().arguments, ["init"])
    }

    func testAddAllUsesAddDot() {
        XCTAssertEqual(GitCommandBuilder.addAll().arguments, ["add", "."])
    }

    func testCommitUsesMessage() {
        XCTAssertEqual(
            GitCommandBuilder.commit(message: "Initial SVN snapshot").arguments,
            ["commit", "-m", "Initial SVN snapshot"]
        )
    }

    func testLogGitSvnMetadataUsesAllCommitBodies() {
        XCTAssertEqual(
            GitCommandBuilder.logGitSvnMetadata().arguments,
            ["log", "--all", "--format=%B"]
        )
    }

    func testSvnFetchUsesGitSvnFetch() {
        XCTAssertEqual(GitCommandBuilder.svnFetch().arguments, ["svn", "fetch"])
    }

    func testPushCommandsUseRemoteAllBranchesAndTags() {
        XCTAssertEqual(GitCommandBuilder.pushAll(remote: "origin").arguments, ["push", "origin", "--all"])
        XCTAssertEqual(GitCommandBuilder.pushTags(remote: "origin").arguments, ["push", "origin", "--tags"])
    }

    func testSvnCloneUsesStandardLayoutAuthorsFileRevisionAndUsername() {
        let layout = GitMigrationRepositoryLayout(
            kind: .standard,
            trunkPath: "trunk",
            branchesPath: "branches",
            tagsPath: "tags",
            confidence: 1
        )

        XCTAssertEqual(
            GitCommandBuilder.svnClone(
                sourceURL: "file:///repo",
                destination: URL(fileURLWithPath: "/tmp/git-repo"),
                authorsFile: URL(fileURLWithPath: "/tmp/authors.txt"),
                layout: layout,
                revisionRange: RevisionRange(start: Revision(1), end: Revision(42)),
                username: "yangchao"
            ).arguments,
            [
                "svn", "clone",
                "--authors-file", "/tmp/authors.txt",
                "--stdlayout",
                "--revision", "1:42",
                "--username", "yangchao",
                "file:///repo",
                "/tmp/git-repo"
            ]
        )
    }

    func testSvnCloneUsesCustomLayoutPathsWhenProvided() {
        let layout = GitMigrationRepositoryLayout(
            kind: .custom,
            trunkPath: "main",
            branchesPath: "dev/*",
            tagsPath: "releases/*",
            confidence: 0.8
        )

        XCTAssertEqual(
            GitCommandBuilder.svnClone(
                sourceURL: "https://svn.example.com/project",
                destination: URL(fileURLWithPath: "/tmp/custom"),
                authorsFile: URL(fileURLWithPath: "/tmp/authors.txt"),
                layout: layout,
                revisionRange: nil,
                username: nil
            ).arguments,
            [
                "svn", "clone",
                "--authors-file", "/tmp/authors.txt",
                "--trunk", "main",
                "--branches", "dev/*",
                "--tags", "releases/*",
                "https://svn.example.com/project",
                "/tmp/custom"
            ]
        )
    }
}
