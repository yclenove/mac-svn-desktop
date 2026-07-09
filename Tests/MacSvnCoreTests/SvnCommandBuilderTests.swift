import XCTest
@testable import MacSvnCore

final class SvnCommandBuilderTests: XCTestCase {
    func testVersionUsesQuietFlag() {
        let command = SvnCommandBuilder.version()
        XCTAssertEqual(command.arguments, ["--version", "--quiet"])
    }

    func testStatusUsesXmlAndNonInteractive() {
        let command = SvnCommandBuilder.status()
        XCTAssertEqual(command.arguments, ["status", "--xml", "--non-interactive"])
    }

    func testCommitUsesUtf8EncodingNonInteractiveMessageAndPaths() {
        let command = SvnCommandBuilder.commit(paths: ["src/a.swift", "中文/文件.txt"], message: "修复：登录超时")
        XCTAssertEqual(command.arguments, [
            "commit", "--encoding", "UTF-8", "--non-interactive",
            "-m", "修复：登录超时",
            "src/a.swift", "中文/文件.txt"
        ])
    }

    func testUpdatePostponesConflictsAndCanTargetRevision() {
        let command = SvnCommandBuilder.update(paths: ["src"], revision: Revision(42))
        XCTAssertEqual(command.arguments, [
            "update", "--accept", "postpone", "--non-interactive", "-r", "42", "src"
        ])
    }

    func testUpdateCanIncludeAuthenticationArgumentsWithoutPassword() {
        let command = SvnCommandBuilder.update(
            paths: ["src"],
            revision: Revision(42),
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "update", "--accept", "postpone", "--non-interactive",
            "--username", "u", "--password-from-stdin",
            "-r", "42", "src"
        ])
        XCTAssertFalse(command.arguments.contains("secret"))
    }

    func testUpdateCanSetDepth() {
        let command = SvnCommandBuilder.update(paths: [], revision: nil, setDepth: .files)

        XCTAssertEqual(command.arguments, [
            "update", "--accept", "postpone", "--non-interactive",
            "--set-depth", "files"
        ])
    }

    func testSwitchUsesPostponeNonInteractiveAuthAndUrl() {
        let command = SvnCommandBuilder.switchTo(
            url: "file:///repo/branches/feature-one",
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "switch", "--accept", "postpone", "--non-interactive",
            "--username", "u", "--password-from-stdin",
            "file:///repo/branches/feature-one"
        ])
    }

    func testMergeUsesPostponeDryRunRangeAuthAndSource() {
        let command = SvnCommandBuilder.merge(
            source: "file:///repo/branches/feature-one",
            range: RevisionRange(start: Revision(2), end: Revision(5)),
            dryRun: true,
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "merge", "--accept", "postpone", "--non-interactive", "--dry-run",
            "--username", "u", "--password-from-stdin",
            "-r", "2:5",
            "file:///repo/branches/feature-one"
        ])
    }

    func testResolveUsesAcceptNonInteractiveAndPath() {
        let command = SvnCommandBuilder.resolve(path: "README.txt", accept: .mineFull)

        XCTAssertEqual(command.arguments, [
            "resolve", "--accept", "mine-full", "--non-interactive", "README.txt"
        ])
    }

    func testResolveCanAcceptTreeConflictSides() {
        XCTAssertEqual(
            SvnCommandBuilder.resolve(path: "tree.txt", accept: .mineConflict).arguments,
            ["resolve", "--accept", "mine-conflict", "--non-interactive", "tree.txt"]
        )
        XCTAssertEqual(
            SvnCommandBuilder.resolve(path: "tree.txt", accept: .theirsConflict).arguments,
            ["resolve", "--accept", "theirs-conflict", "--non-interactive", "tree.txt"]
        )
    }

    func testAddUsesNonInteractiveAndPaths() {
        let command = SvnCommandBuilder.add(paths: ["a.txt", "dir/b.txt"])
        XCTAssertEqual(command.arguments, ["add", "--non-interactive", "a.txt", "dir/b.txt"])
    }

    func testDeleteUsesNonInteractiveAndPaths() {
        let command = SvnCommandBuilder.delete(paths: ["old.txt"])
        XCTAssertEqual(command.arguments, ["delete", "--non-interactive", "old.txt"])
    }

    func testRevertCanBeRecursive() {
        let command = SvnCommandBuilder.revert(paths: ["dir"], recursive: true)
        XCTAssertEqual(command.arguments, ["revert", "--non-interactive", "--recursive", "dir"])
    }

    func testCleanupUsesNonInteractive() {
        let command = SvnCommandBuilder.cleanup()
        XCTAssertEqual(command.arguments, ["cleanup", "--non-interactive"])
    }

    func testDiffCanTargetRevisionRange() {
        let command = SvnCommandBuilder.diff(target: "a.txt", r1: Revision(1), r2: Revision(3))
        XCTAssertEqual(command.arguments, ["diff", "--non-interactive", "-r", "1:3", "a.txt"])
    }

    func testLogUsesXmlVerboseAndBatch() {
        let command = SvnCommandBuilder.log(target: "trunk", from: Revision(20), batch: 100, verbose: true)
        XCTAssertEqual(command.arguments, ["log", "--xml", "-v", "--non-interactive", "-r", "20:0", "-l", "100", "trunk"])
    }

    func testLogCanIncludeAuthenticationArgumentsBeforeTarget() {
        let command = SvnCommandBuilder.log(
            target: "file:///repo/trunk",
            from: Revision(20),
            batch: 50,
            verbose: true,
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "log", "--xml", "-v", "--non-interactive",
            "-r", "20:0",
            "-l", "50",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk"
        ])
    }

    func testListUsesXmlDepthAuthAndUrl() {
        let command = SvnCommandBuilder.list(
            url: "file:///repo/trunk",
            depth: .immediates,
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "list", "--xml", "--non-interactive",
            "--depth", "immediates",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk"
        ])
    }

    func testCatUsesRevisionAuthenticationAndUrl() {
        let command = SvnCommandBuilder.cat(
            url: "file:///repo/trunk/README.txt",
            revision: Revision(7),
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "cat", "--non-interactive",
            "-r", "7",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk/README.txt"
        ])
    }

    func testCheckoutUsesDepthAuthenticationUrlAndDestination() {
        let command = SvnCommandBuilder.checkout(
            url: "file:///repo/trunk",
            to: "/tmp/wc",
            depth: .files,
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "checkout", "--non-interactive",
            "--depth", "files",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk", "/tmp/wc"
        ])
    }

    func testCopyUsesUtf8MessageAuthSourceAndDestination() {
        let command = SvnCommandBuilder.copy(
            source: "file:///repo/trunk",
            destination: "file:///repo/branches/feature-one",
            message: "创建分支：feature-one",
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "copy", "--encoding", "UTF-8", "--non-interactive",
            "-m", "创建分支：feature-one",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk", "file:///repo/branches/feature-one"
        ])
    }

    func testInfoUsesXmlAndNonInteractive() {
        let command = SvnCommandBuilder.info(target: ".")
        XCTAssertEqual(command.arguments, ["info", "--xml", "--non-interactive", "."])
    }

    func testBlameUsesXmlNonInteractiveAndTarget() {
        let command = SvnCommandBuilder.blame(target: "README.txt")

        XCTAssertEqual(command.arguments, ["blame", "--xml", "--non-interactive", "README.txt"])
    }
}
