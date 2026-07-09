import Foundation
import XCTest
@testable import MacSvnCore

struct SvnIntegrationFixture {
    let root: URL
    let repository: URL
    let repositoryURL: String
    let trunkURL: String
    let workingCopy: URL
    let backend: SvnCliBackend
}

class SvnIntegrationTestCase: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func makeFixture() throws -> SvnIntegrationFixture {
        let tools = try requireSvnTools()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSvnCoreIntegration-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("repo", isDirectory: true)
        let importRoot = root.appendingPathComponent("import", isDirectory: true)
        let trunk = importRoot.appendingPathComponent("trunk", isDirectory: true)
        let branches = importRoot.appendingPathComponent("branches", isDirectory: true)
        let tags = importRoot.appendingPathComponent("tags", isDirectory: true)
        let sourceDirectory = trunk.appendingPathComponent("src", isDirectory: true)
        let workingCopy = root.appendingPathComponent("wc", isDirectory: true)

        temporaryRoots.append(root)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: branches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tags, withIntermediateDirectories: true)
        try "hello\n".write(to: trunk.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        try "print('seed')\n".write(to: sourceDirectory.appendingPathComponent("main.txt"), atomically: true, encoding: .utf8)
        try "中文内容\n".write(to: trunk.appendingPathComponent("中文文件.txt"), atomically: true, encoding: .utf8)

        try runTool(executable: tools.svnadmin, arguments: ["create", repository.path], currentDirectory: nil)
        try runTool(
            executable: tools.svn,
            arguments: ["import", importRoot.path, repository.fileURLString, "-m", "initial import", "--non-interactive"],
            currentDirectory: nil
        )

        return SvnIntegrationFixture(
            root: root,
            repository: repository,
            repositoryURL: repository.fileURLString,
            trunkURL: repository.appendingPathComponent("trunk", isDirectory: true).fileURLString,
            workingCopy: workingCopy,
            backend: SvnCliBackend(svnExecutable: tools.svn, runner: ProcessRunner(), timeout: 30)
        )
    }

    private func requireSvnTools() throws -> (svn: String, svnadmin: String) {
        guard let svn = findExecutable(named: "svn") else {
            throw XCTSkip("svn executable is not available.")
        }
        guard let svnadmin = findExecutable(named: "svnadmin") else {
            throw XCTSkip("svnadmin executable is not available.")
        }

        return (svn: svn, svnadmin: svnadmin)
    }

    private func findExecutable(named name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func runTool(executable: String, arguments: [String], currentDirectory: URL?) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging([
            "LC_ALL": "C",
            "LANG": "C"
        ]) { _, new in new }
        process.currentDirectoryURL = currentDirectory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail("Command failed: \(executable) \(arguments.joined(separator: " "))\n\(stdout)\(stderr)")
            throw SvnIntegrationToolError.commandFailed
        }
    }
}

private enum SvnIntegrationToolError: Error {
    case commandFailed
}

private extension URL {
    var fileURLString: String {
        absoluteString
    }
}
