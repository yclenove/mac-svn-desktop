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
}
