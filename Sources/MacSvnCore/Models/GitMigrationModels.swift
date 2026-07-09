import Foundation

public enum GitMigrationMode: Equatable, Sendable {
    case snapshot
}

public enum GitMigrationStep: Equatable, Sendable {
    case svnExport
    case gitInit
    case gitAdd
    case gitCommit
}

public struct GitMigrationReport: Equatable, Sendable {
    public let mode: GitMigrationMode
    public let sourceURL: String
    public let destinationPath: String
    public let revision: Revision?
    public let commitMessage: String
    public let completedSteps: [GitMigrationStep]

    public init(
        mode: GitMigrationMode,
        sourceURL: String,
        destinationPath: String,
        revision: Revision?,
        commitMessage: String,
        completedSteps: [GitMigrationStep]
    ) {
        self.mode = mode
        self.sourceURL = sourceURL
        self.destinationPath = destinationPath
        self.revision = revision
        self.commitMessage = commitMessage
        self.completedSteps = completedSteps
    }
}

public enum GitMigrationError: Error, Equatable, Sendable {
    case emptySourceURL
    case emptyCommitMessage
    case destinationNotEmpty(path: String)
}
