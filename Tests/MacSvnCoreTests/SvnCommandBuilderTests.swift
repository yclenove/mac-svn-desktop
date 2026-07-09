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

    func testInfoUsesXmlAndNonInteractive() {
        let command = SvnCommandBuilder.info(target: ".")
        XCTAssertEqual(command.arguments, ["info", "--xml", "--non-interactive", "."])
    }
}
