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
