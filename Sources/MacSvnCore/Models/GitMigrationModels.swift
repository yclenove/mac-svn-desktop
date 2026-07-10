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
    /// 源仓库 revision 全集（供迁移后对账，NFR-14）。
    public let sourceRevisions: [Revision]

    public init(
        repositoryRoot: String,
        environment: GitMigrationEnvironmentStatus,
        layout: GitMigrationRepositoryLayout,
        authors: [GitMigrationAuthor],
        latestRevision: Revision?,
        oldestRevision: Revision?,
        totalRevisionCount: Int,
        sourceRevisions: [Revision] = []
    ) {
        self.repositoryRoot = repositoryRoot
        self.environment = environment
        self.layout = layout
        self.authors = authors
        self.latestRevision = latestRevision
        self.oldestRevision = oldestRevision
        self.totalRevisionCount = totalRevisionCount
        self.sourceRevisions = sourceRevisions
    }
}

public enum GitMigrationSourceAnalysisError: Error, Equatable, Sendable {
    case emptyRepositoryRoot
}

public struct GitSvnRevisionMetadata: Equatable, Sendable {
    public let revision: Revision

    public init(revision: Revision) {
        self.revision = revision
    }
}

public struct GitMigrationRevisionReconciliationReport: Equatable, Sendable {
    public let sourceRevisionCount: Int
    public let migratedRevisionCount: Int
    public let missingRevisions: [Revision]
    public let unexpectedRevisions: [Revision]

    public init(
        sourceRevisionCount: Int,
        migratedRevisionCount: Int,
        missingRevisions: [Revision],
        unexpectedRevisions: [Revision]
    ) {
        self.sourceRevisionCount = sourceRevisionCount
        self.migratedRevisionCount = migratedRevisionCount
        self.missingRevisions = missingRevisions
        self.unexpectedRevisions = unexpectedRevisions
    }

    public var isConsistent: Bool {
        missingRevisions.isEmpty && unexpectedRevisions.isEmpty
    }
}

public struct GitMigrationLargeFileFinding: Equatable, Sendable {
    public let path: String
    public let sizeBytes: Int
    public let thresholdBytes: Int

    public init(path: String, sizeBytes: Int, thresholdBytes: Int) {
        self.path = path
        self.sizeBytes = sizeBytes
        self.thresholdBytes = thresholdBytes
    }
}

public struct GitMigrationCleanupPlan: Equatable, Sendable {
    public let largeFiles: [GitMigrationLargeFileFinding]
    public let excludedPaths: [String]
    public let gitIgnoreContents: String

    public init(
        largeFiles: [GitMigrationLargeFileFinding],
        excludedPaths: [String],
        gitIgnoreContents: String
    ) {
        self.largeFiles = largeFiles
        self.excludedPaths = excludedPaths
        self.gitIgnoreContents = gitIgnoreContents
    }

    public var hasLargeFileWarnings: Bool {
        !largeFiles.isEmpty
    }
}

public enum GitMigrationCleanupError: Error, Equatable, Sendable {
    case invalidLargeFileThreshold(Int)
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

public enum GitMigrationSyncError: Error, Equatable, Sendable {
    case emptySourceURL
    case emptyRepositoryPath
    case recordNotFound(UUID)
    case invalidScheduleInterval(Int)
}

public struct GitMigrationSyncRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var sourceURL: String
    public var repositoryPath: String
    public var targetRemote: String?
    public var createdAt: Date
    public var lastSyncedAt: Date?
    public var lastSyncedRevision: Revision?
    public var isScheduledSyncEnabled: Bool
    public var syncIntervalMinutes: Int?

    public init(
        id: UUID,
        sourceURL: String,
        repositoryPath: String,
        targetRemote: String?,
        createdAt: Date,
        lastSyncedAt: Date?,
        lastSyncedRevision: Revision?,
        isScheduledSyncEnabled: Bool = false,
        syncIntervalMinutes: Int? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.repositoryPath = repositoryPath
        self.targetRemote = targetRemote
        self.createdAt = createdAt
        self.lastSyncedAt = lastSyncedAt
        self.lastSyncedRevision = lastSyncedRevision
        self.isScheduledSyncEnabled = isScheduledSyncEnabled
        self.syncIntervalMinutes = syncIntervalMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceURL
        case repositoryPath
        case targetRemote
        case createdAt
        case lastSyncedAt
        case lastSyncedRevision
        case isScheduledSyncEnabled
        case syncIntervalMinutes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceURL = try container.decode(String.self, forKey: .sourceURL)
        repositoryPath = try container.decode(String.self, forKey: .repositoryPath)
        targetRemote = try container.decodeIfPresent(String.self, forKey: .targetRemote)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        lastSyncedRevision = try container.decodeIfPresent(Revision.self, forKey: .lastSyncedRevision)
        isScheduledSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .isScheduledSyncEnabled) ?? false
        syncIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .syncIntervalMinutes)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encode(repositoryPath, forKey: .repositoryPath)
        try container.encodeIfPresent(targetRemote, forKey: .targetRemote)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastSyncedAt, forKey: .lastSyncedAt)
        try container.encodeIfPresent(lastSyncedRevision, forKey: .lastSyncedRevision)
        try container.encode(isScheduledSyncEnabled, forKey: .isScheduledSyncEnabled)
        try container.encodeIfPresent(syncIntervalMinutes, forKey: .syncIntervalMinutes)
    }
}

public struct GitMigrationSyncListFile: Codable, Equatable, Sendable {
    public var version: Int
    public var records: [GitMigrationSyncRecord]

    public init(version: Int = 1, records: [GitMigrationSyncRecord] = []) {
        self.version = version
        self.records = records
    }
}

public enum GitMigrationSyncStep: Equatable, Sendable {
    case gitSvnFetch
    case revisionScan
    case gitPushBranches
    case gitPushTags
}

public struct GitMigrationSyncReport: Equatable, Sendable {
    public let recordID: UUID
    public let repositoryPath: String
    public let completedSteps: [GitMigrationSyncStep]
    public let latestRevision: Revision?
    public let updatedRecord: GitMigrationSyncRecord

    public init(
        recordID: UUID,
        repositoryPath: String,
        completedSteps: [GitMigrationSyncStep],
        latestRevision: Revision?,
        updatedRecord: GitMigrationSyncRecord
    ) {
        self.recordID = recordID
        self.repositoryPath = repositoryPath
        self.completedSteps = completedSteps
        self.latestRevision = latestRevision
        self.updatedRecord = updatedRecord
    }
}

public struct GitMigrationScheduledSyncReport: Equatable, Sendable {
    public let attemptedRecordIDs: [UUID]
    public let completedReports: [GitMigrationSyncReport]
    public let failedRecordIDs: [UUID]

    public init(
        attemptedRecordIDs: [UUID],
        completedReports: [GitMigrationSyncReport],
        failedRecordIDs: [UUID]
    ) {
        self.attemptedRecordIDs = attemptedRecordIDs
        self.completedReports = completedReports
        self.failedRecordIDs = failedRecordIDs
    }
}
