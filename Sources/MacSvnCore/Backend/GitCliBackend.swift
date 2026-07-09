import Foundation

public struct GitCliBackend: GitBackend {
    private let gitExecutable: String
    private let runner: any ProcessRunning
    private let timeout: TimeInterval

    public init(gitExecutable: String = "git", runner: any ProcessRunning, timeout: TimeInterval = 120) {
        self.gitExecutable = gitExecutable
        self.runner = runner
        self.timeout = timeout
    }

    public func initRepository(at repository: URL) async throws {
        try await run(GitCommandBuilder.initRepository(), repository: repository)
    }

    public func addAll(repository: URL) async throws {
        try await run(GitCommandBuilder.addAll(), repository: repository)
    }

    public func commit(repository: URL, message: String) async throws {
        try await run(GitCommandBuilder.commit(message: message), repository: repository)
    }

    public func svnClone(
        sourceURL: String,
        destination: URL,
        authorsFile: URL,
        layout: GitMigrationRepositoryLayout,
        revisionRange: RevisionRange?,
        username: String?
    ) async throws {
        let command = GitCommandBuilder.svnClone(
            sourceURL: sourceURL,
            destination: destination,
            authorsFile: authorsFile,
            layout: layout,
            revisionRange: revisionRange,
            username: username
        )

        try await run(command, repository: nil)
    }

    private func run(_ command: GitCommand, repository: URL?) async throws {
        let result = try await runner.run(
            executable: gitExecutable,
            arguments: command.arguments,
            stdin: nil,
            currentDirectory: repository?.path,
            timeout: timeout
        )

        guard result.exitCode == 0 else {
            throw SvnError.other(code: Int(result.exitCode), stderr: result.stderr)
        }
    }
}
