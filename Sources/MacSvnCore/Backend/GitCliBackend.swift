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

    public func gitSvnRevisions(repository: URL) async throws -> [GitSvnRevisionMetadata] {
        let result = try await runReturningResult(
            GitCommandBuilder.logGitSvnMetadata(),
            repository: repository
        )
        let output = String(data: result.stdout, encoding: .utf8) ?? ""
        return GitSvnMetadataParser.parseRevisions(from: output)
    }

    public func svnFetch(repository: URL) async throws {
        try await run(GitCommandBuilder.svnFetch(), repository: repository)
    }

    public func pushAll(repository: URL, remote: String) async throws {
        try await run(GitCommandBuilder.pushAll(remote: remote), repository: repository)
    }

    public func pushTags(repository: URL, remote: String) async throws {
        try await run(GitCommandBuilder.pushTags(remote: remote), repository: repository)
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
        _ = try await runReturningResult(command, repository: repository)
    }

    private func runReturningResult(_ command: GitCommand, repository: URL?) async throws -> ProcessResult {
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

        return result
    }
}
