import Foundation

public enum GitMigrationMode: Equatable, Sendable {
    case snapshot
    case historyPreserving
}

public enum GitMigrationStep: Equatable, Sendable {
    case svnExport
    case gitInit
    case gitAdd
    case gitCommit
    case authorsFile
    case gitSvnClone
}

public struct GitMigrationToolStatus: Equatable, Sendable {
    public let isAvailable: Bool
    public let versionOutput: String?
    public let errorSummary: String?

    public init(isAvailable: Bool, versionOutput: String?, errorSummary: String?) {
        self.isAvailable = isAvailable
        self.versionOutput = versionOutput
        self.errorSummary = errorSummary
    }
}

public struct GitMigrationEnvironmentStatus: Equatable, Sendable {
    public let git: GitMigrationToolStatus
    public let gitSvn: GitMigrationToolStatus

    public init(git: GitMigrationToolStatus, gitSvn: GitMigrationToolStatus) {
        self.git = git
        self.gitSvn = gitSvn
    }

    public var isReadyForHistoryMigration: Bool {
        git.isAvailable && gitSvn.isAvailable
    }
}

public struct GitMigrationReport: Equatable, Sendable {
    public let mode: GitMigrationMode
    public let sourceURL: String
    public let destinationPath: String
    public let revision: Revision?
    public let commitMessage: String
    public let completedSteps: [GitMigrationStep]
    public let authorsFilePath: String?
    public let layout: GitMigrationRepositoryLayout?
    public let revisionRange: RevisionRange?

    public init(
        mode: GitMigrationMode,
        sourceURL: String,
        destinationPath: String,
        revision: Revision?,
        commitMessage: String,
        completedSteps: [GitMigrationStep],
        authorsFilePath: String? = nil,
        layout: GitMigrationRepositoryLayout? = nil,
        revisionRange: RevisionRange? = nil
    ) {
        self.mode = mode
        self.sourceURL = sourceURL
        self.destinationPath = destinationPath
        self.revision = revision
        self.commitMessage = commitMessage
        self.completedSteps = completedSteps
        self.authorsFilePath = authorsFilePath
        self.layout = layout
        self.revisionRange = revisionRange
    }
}

public enum GitMigrationError: Error, Equatable, Sendable {
    case emptySourceURL
    case emptyCommitMessage
    case destinationNotEmpty(path: String)
}

public enum GitMigrationRepositoryLayoutKind: Equatable, Sendable {
    case standard
    case custom
}

public struct GitMigrationRepositoryLayout: Equatable, Sendable {
    public let kind: GitMigrationRepositoryLayoutKind
    public let trunkPath: String?
    public let branchesPath: String?
    public let tagsPath: String?
    public let confidence: Double

    public init(
        kind: GitMigrationRepositoryLayoutKind,
        trunkPath: String?,
        branchesPath: String?,
        tagsPath: String?,
        confidence: Double
    ) {
        self.kind = kind
        self.trunkPath = trunkPath
        self.branchesPath = branchesPath
        self.tagsPath = tagsPath
        self.confidence = confidence
    }
}

public struct GitMigrationAuthor: Equatable, Sendable {
    public let svnUsername: String

    public init(svnUsername: String) {
        self.svnUsername = svnUsername
    }
}

public struct GitMigrationSourceAnalysis: Equatable, Sendable {
    public let repositoryRoot: String
    public let environment: GitMigrationEnvironmentStatus
    public let layout: GitMigrationRepositoryLayout
    public let authors: [GitMigrationAuthor]
    public let latestRevision: Revision?
    public let oldestRevision: Revision?
    public let totalRevisionCount: Int

    public init(
        repositoryRoot: String,
        environment: GitMigrationEnvironmentStatus,
        layout: GitMigrationRepositoryLayout,
        authors: [GitMigrationAuthor],
        latestRevision: Revision?,
        oldestRevision: Revision?,
        totalRevisionCount: Int
    ) {
        self.repositoryRoot = repositoryRoot
        self.environment = environment
        self.layout = layout
        self.authors = authors
        self.latestRevision = latestRevision
        self.oldestRevision = oldestRevision
        self.totalRevisionCount = totalRevisionCount
    }
}

public enum GitMigrationSourceAnalysisError: Error, Equatable, Sendable {
    case emptyRepositoryRoot
}

public struct GitMigrationAuthorMapping: Equatable, Sendable {
    public let svnUsername: String
    public var gitName: String
    public var gitEmail: String

    public init(svnUsername: String, gitName: String, gitEmail: String) {
        self.svnUsername = svnUsername
        self.gitName = gitName
        self.gitEmail = gitEmail
    }
}

public struct GitMigrationAuthorMappingCoverage: Equatable, Sendable {
    public let totalCount: Int
    public let coveredCount: Int

    public init(totalCount: Int, coveredCount: Int) {
        self.totalCount = totalCount
        self.coveredCount = coveredCount
    }

    public var isComplete: Bool {
        totalCount > 0 && totalCount == coveredCount
    }
}

public enum GitMigrationAuthorMappingError: Error, Equatable, Sendable {
    case incompleteAuthors([String])
    case invalidAuthorsFileLine(String)
}
