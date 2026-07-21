import Foundation

public enum SvnRepositoryCreationError: Error, Equatable, Sendable {
    case unsafeDestination
}

public protocol RepositoryCreating: Sendable {
    func create(at destination: URL) async throws
}

public struct SvnRepositoryCreator: RepositoryCreating, Sendable {
    private let svnadminExecutable: String
    private let runner: any ProcessRunning
    private let timeout: TimeInterval

    public init(
        svnadminExecutable: String,
        runner: any ProcessRunning,
        timeout: TimeInterval = 120
    ) {
        self.svnadminExecutable = svnadminExecutable
        self.runner = runner
        self.timeout = timeout
    }

    public func create(at destination: URL) async throws {
        let destination = destination.standardizedFileURL
        guard destination.isFileURL, destination.path != "/" else {
            throw SvnRepositoryCreationError.unsafeDestination
        }

        let result = try await runner.run(
            executable: svnadminExecutable,
            arguments: ["create", "--fs-type", "fsfs", destination.path],
            stdin: nil,
            currentDirectory: nil,
            timeout: timeout
        )
        guard result.exitCode == 0 else {
            throw SvnErrorMapper.map(exitCode: result.exitCode, stderr: result.stderr)
        }
    }
}
