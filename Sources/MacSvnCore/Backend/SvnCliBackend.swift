import Foundation

public struct SvnCliBackend: SvnBackend {
    private let svnExecutable: String
    private let runner: any ProcessRunning
    private let timeout: TimeInterval

    public init(svnExecutable: String, runner: any ProcessRunning, timeout: TimeInterval = 120) {
        self.svnExecutable = svnExecutable
        self.runner = runner
        self.timeout = timeout
    }

    public func version() async throws -> SvnVersion {
        let command = SvnCommandBuilder.version()
        let result = try await run(command, currentDirectory: nil, stdin: nil)
        return try SvnVersion.parse(String(decoding: result.stdout, as: UTF8.self))
    }

    public func status(wc: URL) async throws -> [FileStatus] {
        let command = SvnCommandBuilder.status()
        let result = try await run(command, currentDirectory: wc.path, stdin: nil)
        return try StatusXMLParser.parse(result.stdout)
    }

    public func update(wc: URL, paths: [String] = [], revision: Revision? = nil) async throws -> UpdateSummary {
        let command = SvnCommandBuilder.update(paths: paths, revision: revision)
        let result = try await run(command, currentDirectory: wc.path, stdin: nil)
        return try UpdateOutputParser.parse(String(decoding: result.stdout, as: UTF8.self))
    }

    public func commit(wc: URL, paths: [String], message: String, auth: Credential?) async throws -> Revision {
        let authArguments = try AuthArguments.build(credential: auth)
        let command = SvnCommandBuilder.commit(paths: paths, message: message, authArguments: authArguments.arguments)
        let result = try await run(command, currentDirectory: wc.path, stdin: authArguments.stdin)
        return try CommitOutputParser.parseRevision(from: String(decoding: result.stdout, as: UTF8.self))
    }

    public func add(wc: URL, paths: [String]) async throws {
        _ = try await run(SvnCommandBuilder.add(paths: paths), currentDirectory: wc.path, stdin: nil)
    }

    public func delete(wc: URL, paths: [String]) async throws {
        _ = try await run(SvnCommandBuilder.delete(paths: paths), currentDirectory: wc.path, stdin: nil)
    }

    public func revert(wc: URL, paths: [String], recursive: Bool) async throws {
        _ = try await run(SvnCommandBuilder.revert(paths: paths, recursive: recursive), currentDirectory: wc.path, stdin: nil)
    }

    public func cleanup(wc: URL) async throws {
        _ = try await run(SvnCommandBuilder.cleanup(), currentDirectory: wc.path, stdin: nil)
    }

    public func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        let result = try await run(SvnCommandBuilder.diff(target: target, r1: r1, r2: r2), currentDirectory: wc.path, stdin: nil)
        return String(decoding: result.stdout, as: UTF8.self)
    }

    public func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry] {
        let command = SvnCommandBuilder.log(target: target, from: from, batch: batch, verbose: verbose)
        let result = try await run(command, currentDirectory: wc.path, stdin: nil)
        return try LogXMLParser.parse(result.stdout)
    }

    public func checkout(url: String, to destination: URL) async throws {
        _ = try await run(SvnCommandBuilder.checkout(url: url, to: destination.path), currentDirectory: nil, stdin: nil)
    }

    public func info(wc: URL, target: String) async throws -> SvnInfo {
        let result = try await run(SvnCommandBuilder.info(target: target), currentDirectory: wc.path, stdin: nil)
        return try InfoXMLParser.parse(result.stdout)
    }

    private func run(_ command: SvnCommand, currentDirectory: String?, stdin: Data?) async throws -> ProcessResult {
        let result = try await runner.run(
            executable: svnExecutable,
            arguments: command.arguments,
            stdin: stdin,
            currentDirectory: currentDirectory,
            timeout: timeout
        )

        guard result.exitCode == 0 else {
            throw SvnErrorMapper.map(exitCode: result.exitCode, stderr: result.stderr)
        }

        return result
    }
}
