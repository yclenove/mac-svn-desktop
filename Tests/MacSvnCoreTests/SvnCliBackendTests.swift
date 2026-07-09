import Foundation
import XCTest
@testable import MacSvnCore

final class SvnCliBackendTests: XCTestCase {
    func testVersionRunsQuietVersionAndParsesOutput() async throws {
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data("1.14.5\n".utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        let version = try await backend.version()

        XCTAssertEqual(version, SvnVersion(major: 1, minor: 14, patch: 5))
        XCTAssertEqual(runner.calls.single?.arguments, ["--version", "--quiet"])
    }

    func testStatusRunsInWorkingCopyAndParsesXml() async throws {
        let xml = """
        <status><target path="."><entry path="a.txt"><wc-status item="modified" revision="3"/></entry></target></status>
        """
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(xml.utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        let statuses = try await backend.status(wc: wc)

        XCTAssertEqual(statuses, [FileStatus(path: "a.txt", itemStatus: .modified, revision: Revision(3), isTreeConflict: false)])
        XCTAssertEqual(runner.calls.single?.currentDirectory, "/tmp/wc")
    }

    func testInfoRunsInWorkingCopyAndParsesXml() async throws {
        let xml = """
        <info><entry path="." revision="3" kind="dir"><url>file:///repo/trunk</url><repository><root>file:///repo</root></repository></entry></info>
        """
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(xml.utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        let info = try await backend.info(wc: wc, target: ".")

        XCTAssertEqual(info, SvnInfo(path: ".", url: "file:///repo/trunk", repositoryRoot: "file:///repo", revision: Revision(3), kind: "dir"))
        XCTAssertEqual(runner.calls.single?.arguments, ["info", "--xml", "--non-interactive", "."])
        XCTAssertEqual(runner.calls.single?.currentDirectory, "/tmp/wc")
    }

    func testBlameRunsInWorkingCopyAndParsesXml() async throws {
        let xml = """
        <blame><target path="README.txt"><entry line-number="1"><commit revision="7"><author>yangchao</author><date>2026-07-09T06:00:00.000000Z</date></commit></entry></target></blame>
        """
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(xml.utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        let lines = try await backend.blame(wc: wc, target: "README.txt")

        XCTAssertEqual(lines, [
            BlameLine(
                lineNumber: 1,
                revision: Revision(7),
                author: "yangchao",
                date: ISO8601DateFormatter.svnXML.date(from: "2026-07-09T06:00:00.000000Z")
            )
        ])
        XCTAssertEqual(runner.calls.single?.arguments, ["blame", "--xml", "--non-interactive", "README.txt"])
        XCTAssertEqual(runner.calls.single?.currentDirectory, "/tmp/wc")
    }

    func testPropertyQueriesRunInWorkingCopyAndParseXml() async throws {
        let xml = """
        <properties><target path="README.txt"><property name="svn:eol-style">native</property></target></properties>
        """
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(xml.utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        let properties = try await backend.properties(wc: wc, target: "README.txt")

        XCTAssertEqual(properties, [
            SvnProperty(target: "README.txt", name: "svn:eol-style", value: "native")
        ])
        XCTAssertEqual(runner.calls.single?.arguments, ["proplist", "--xml", "--verbose", "--non-interactive", "README.txt"])
        XCTAssertEqual(runner.calls.single?.currentDirectory, "/tmp/wc")
    }

    func testPropertyValueReturnsFirstMatchingProperty() async throws {
        let xml = """
        <properties><target path="README.txt"><property name="svn:eol-style">native</property></target></properties>
        """
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(xml.utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        let property = try await backend.propertyValue(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            target: "README.txt",
            name: "svn:eol-style"
        )

        XCTAssertEqual(property, SvnProperty(target: "README.txt", name: "svn:eol-style", value: "native"))
        XCTAssertEqual(runner.calls.single?.arguments, ["propget", "--xml", "--non-interactive", "svn:eol-style", "README.txt"])
    }

    func testPropertyWritesRunInWorkingCopy() async throws {
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        try await backend.setProperty(wc: wc, target: "README.txt", name: "custom:reviewer", value: "杨超")
        try await backend.deleteProperty(wc: wc, target: "README.txt", name: "custom:reviewer")

        XCTAssertEqual(runner.calls.map(\.arguments), [
            ["propset", "--non-interactive", "custom:reviewer", "杨超", "README.txt"],
            ["propdel", "--non-interactive", "custom:reviewer", "README.txt"]
        ])
        XCTAssertEqual(runner.calls.map(\.currentDirectory), ["/tmp/wc", "/tmp/wc"])
    }

    func testLockStatusRunsInWorkingCopyAndParsesXml() async throws {
        let xml = """
        <status><target path="."><entry path="README.txt"><wc-status item="normal" revision="1"/><repos-status item="none"><lock><token>t</token><owner>u</owner></lock></repos-status></entry></target></status>
        """
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(xml.utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        let locks = try await backend.locks(wc: URL(fileURLWithPath: "/tmp/wc"), targets: ["README.txt"])

        XCTAssertEqual(locks.map(\.target), ["README.txt"])
        XCTAssertEqual(locks.first?.owner, "u")
        XCTAssertEqual(runner.calls.single?.arguments, ["status", "--xml", "--show-updates", "--non-interactive", "README.txt"])
        XCTAssertEqual(runner.calls.single?.currentDirectory, "/tmp/wc")
    }

    func testLockAndUnlockRunInWorkingCopy() async throws {
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        try await backend.lock(wc: wc, paths: ["README.txt"], message: "锁定：编辑中", force: true)
        try await backend.unlock(wc: wc, paths: ["README.txt"], force: true)

        XCTAssertEqual(runner.calls.map(\.arguments), [
            ["lock", "--encoding", "UTF-8", "--non-interactive", "--force", "-m", "锁定：编辑中", "README.txt"],
            ["unlock", "--non-interactive", "--force", "README.txt"]
        ])
        XCTAssertEqual(runner.calls.map(\.currentDirectory), ["/tmp/wc", "/tmp/wc"])
    }

    func testCommitPassesAuthStdinAndParsesRevision() async throws {
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data("Committed revision 42.\n".utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        let revision = try await backend.commit(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            paths: ["a.txt"],
            message: "修复：登录超时",
            auth: Credential(username: "u", password: "p")
        )

        XCTAssertEqual(revision, Revision(42))
        XCTAssertEqual(runner.calls.single?.stdin, Data("p\n".utf8))
        XCTAssertEqual(runner.calls.single?.arguments, [
            "commit", "--encoding", "UTF-8", "--non-interactive",
            "-m", "修复：登录超时",
            "--username", "u", "--password-from-stdin",
            "a.txt"
        ])
    }

    func testUpdatePassesAuthStdinWithoutLeakingPasswordInArguments() async throws {
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data("Updated to revision 9.\n".utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        let summary = try await backend.update(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            paths: ["src"],
            revision: Revision(9),
            setDepth: .immediates,
            auth: Credential(username: "u", password: "secret")
        )

        XCTAssertEqual(summary.revision, Revision(9))
        XCTAssertEqual(runner.calls.single?.stdin, Data("secret\n".utf8))
        XCTAssertEqual(runner.calls.single?.arguments, [
            "update", "--accept", "postpone", "--non-interactive",
            "--username", "u", "--password-from-stdin",
            "-r", "9",
            "--set-depth", "immediates",
            "src"
        ])
        XCTAssertFalse(runner.calls.single?.arguments.contains("secret") ?? true)
    }

    func testSwitchPassesAuthStdinRunsInWorkingCopyAndParsesSummary() async throws {
        let output = """
        U    README.txt
        Updated to revision 9.
        """
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(output.utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        let summary = try await backend.switchTo(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            url: "file:///repo/branches/feature-one",
            auth: Credential(username: "u", password: "secret")
        )

        XCTAssertEqual(summary, UpdateSummary(updated: 1, revision: Revision(9)))
        XCTAssertEqual(runner.calls.single?.stdin, Data("secret\n".utf8))
        XCTAssertEqual(runner.calls.single?.currentDirectory, "/tmp/wc")
        XCTAssertEqual(runner.calls.single?.arguments, [
            "switch", "--accept", "postpone", "--non-interactive",
            "--username", "u", "--password-from-stdin",
            "file:///repo/branches/feature-one"
        ])
        XCTAssertFalse(runner.calls.single?.arguments.contains("secret") ?? true)
    }

    func testMergePassesAuthStdinRunsInWorkingCopyAndParsesSummary() async throws {
        let output = "U    README.txt\n"
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(output.utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        let summary = try await backend.merge(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            source: "file:///repo/branches/feature-one",
            range: RevisionRange(start: Revision(2), end: Revision(5)),
            dryRun: true,
            auth: Credential(username: "u", password: "secret")
        )

        XCTAssertEqual(summary.updated, 1)
        XCTAssertEqual(summary.affectedPaths, [
            MergeAffectedPath(action: .updated, path: "README.txt")
        ])
        XCTAssertEqual(runner.calls.single?.stdin, Data("secret\n".utf8))
        XCTAssertEqual(runner.calls.single?.currentDirectory, "/tmp/wc")
        XCTAssertEqual(runner.calls.single?.arguments, [
            "merge", "--accept", "postpone", "--non-interactive", "--dry-run",
            "--username", "u", "--password-from-stdin",
            "-r", "2:5",
            "file:///repo/branches/feature-one"
        ])
        XCTAssertFalse(runner.calls.single?.arguments.contains("secret") ?? true)
    }

    func testResolveRunsInWorkingCopy() async throws {
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        try await backend.resolve(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            path: "README.txt",
            accept: .working
        )

        XCTAssertEqual(runner.calls.single?.currentDirectory, "/tmp/wc")
        XCTAssertEqual(runner.calls.single?.arguments, [
            "resolve", "--accept", "working", "--non-interactive", "README.txt"
        ])
    }

    func testApplyPatchRunsPatchInWorkingCopy() async throws {
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        try await backend.applyPatch(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            patchFile: URL(fileURLWithPath: "/tmp/shelf.patch")
        )

        XCTAssertEqual(runner.calls.single?.currentDirectory, "/tmp/wc")
        XCTAssertEqual(runner.calls.single?.arguments, ["patch", "--non-interactive", "/tmp/shelf.patch"])
    }

    func testCheckoutPassesDepthAuthStdinAndRunsOutsideWorkingCopy() async throws {
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        try await backend.checkout(
            url: "file:///repo/trunk",
            to: URL(fileURLWithPath: "/tmp/wc"),
            depth: .empty,
            auth: Credential(username: "u", password: "secret")
        )

        XCTAssertEqual(runner.calls.single?.stdin, Data("secret\n".utf8))
        XCTAssertEqual(runner.calls.single?.currentDirectory, nil)
        XCTAssertEqual(runner.calls.single?.arguments, [
            "checkout", "--non-interactive",
            "--depth", "empty",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk", "/tmp/wc"
        ])
        XCTAssertFalse(runner.calls.single?.arguments.contains("secret") ?? true)
    }

    func testCopyPassesAuthStdinRunsWithoutWorkingCopyAndParsesRevision() async throws {
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data("Committed revision 12.\n".utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        let revision = try await backend.copy(
            source: "file:///repo/trunk",
            destination: "file:///repo/branches/feature-one",
            message: "创建分支：feature-one",
            auth: Credential(username: "u", password: "secret")
        )

        XCTAssertEqual(revision, Revision(12))
        XCTAssertEqual(runner.calls.single?.stdin, Data("secret\n".utf8))
        XCTAssertEqual(runner.calls.single?.currentDirectory, nil)
        XCTAssertEqual(runner.calls.single?.arguments, [
            "copy", "--encoding", "UTF-8", "--non-interactive",
            "-m", "创建分支：feature-one",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk", "file:///repo/branches/feature-one"
        ])
        XCTAssertFalse(runner.calls.single?.arguments.contains("secret") ?? true)
    }

    func testListPassesDepthAuthStdinAndParsesEntries() async throws {
        let xml = """
        <lists><list path="file:///repo/trunk"><entry kind="file"><name>README.txt</name><size>5</size><commit revision="2"><author>a</author></commit></entry></list></lists>
        """
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(xml.utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        let entries = try await backend.list(
            url: "file:///repo/trunk",
            depth: .immediates,
            auth: Credential(username: "u", password: "secret")
        )

        XCTAssertEqual(entries.map(\.name), ["README.txt"])
        XCTAssertEqual(runner.calls.single?.stdin, Data("secret\n".utf8))
        XCTAssertEqual(runner.calls.single?.arguments, [
            "list", "--xml", "--non-interactive",
            "--depth", "immediates",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk"
        ])
        XCTAssertFalse(runner.calls.single?.arguments.contains("secret") ?? true)
    }

    func testRemoteLogPassesAuthStdinRunsWithoutWorkingCopyAndParsesEntries() async throws {
        let xml = """
        <log><logentry revision="7"><author>a</author><msg>remote msg</msg></logentry></log>
        """
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data(xml.utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        let entries = try await backend.remoteLog(
            url: "file:///repo/trunk",
            from: Revision(7),
            batch: 10,
            verbose: true,
            auth: Credential(username: "u", password: "secret")
        )

        XCTAssertEqual(entries.map(\.revision), [Revision(7)])
        XCTAssertEqual(entries.first?.message, "remote msg")
        XCTAssertEqual(runner.calls.single?.stdin, Data("secret\n".utf8))
        XCTAssertEqual(runner.calls.single?.currentDirectory, nil)
        XCTAssertEqual(runner.calls.single?.arguments, [
            "log", "--xml", "-v", "--non-interactive",
            "-r", "7:0",
            "-l", "10",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk"
        ])
        XCTAssertFalse(runner.calls.single?.arguments.contains("secret") ?? true)
    }

    func testCatPassesRevisionAuthStdinAndReturnsData() async throws {
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data("hello\n".utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        let data = try await backend.cat(
            url: "file:///repo/trunk/README.txt",
            revision: Revision(7),
            sizeLimit: 10,
            auth: Credential(username: "u", password: "secret")
        )

        XCTAssertEqual(String(data: data, encoding: .utf8), "hello\n")
        XCTAssertEqual(runner.calls.single?.stdin, Data("secret\n".utf8))
        XCTAssertEqual(runner.calls.single?.arguments, [
            "cat", "--non-interactive",
            "-r", "7",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk/README.txt"
        ])
        XCTAssertFalse(runner.calls.single?.arguments.contains("secret") ?? true)
    }

    func testCatThrowsFileTooLargeWhenOutputExceedsLimit() async {
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 0, stdout: Data("abcdef".utf8), stderr: "", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        do {
            _ = try await backend.cat(url: "file:///repo/trunk/big.txt", revision: nil, sizeLimit: 5, auth: nil)
            XCTFail("Expected fileTooLarge")
        } catch let error as SvnError {
            XCTAssertEqual(error, .fileTooLarge(limit: 5, actual: 6))
        } catch {
            XCTFail("Expected SvnError, got \(error)")
        }
    }

    func testNonZeroExitMapsSvnError() async {
        let runner = RecordingProcessRunner(result: ProcessResult(exitCode: 1, stdout: Data(), stderr: "svn: E170001: auth failed", duration: 0.01))
        let backend = SvnCliBackend(svnExecutable: "/usr/bin/svn", runner: runner)

        do {
            _ = try await backend.version()
            XCTFail("Expected authentication error")
        } catch let error as SvnError {
            XCTAssertEqual(error, .authentication)
        } catch {
            XCTFail("Expected SvnError, got \(error)")
        }
    }
}

private final class RecordingProcessRunner: ProcessRunning, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let stdin: Data?
        let currentDirectory: String?
        let timeout: TimeInterval
    }

    private(set) var calls: [Call] = []
    let result: ProcessResult

    init(result: ProcessResult) {
        self.result = result
    }

    func run(
        executable: String,
        arguments: [String],
        stdin: Data?,
        currentDirectory: String?,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        calls.append(Call(
            executable: executable,
            arguments: arguments,
            stdin: stdin,
            currentDirectory: currentDirectory,
            timeout: timeout
        ))
        return result
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
