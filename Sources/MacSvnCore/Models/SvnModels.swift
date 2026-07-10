import Foundation

public struct SvnVersion: Equatable, Comparable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func parse(_ output: String) throws -> SvnVersion {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".")

        guard
            parts.count == 3,
            let major = Int(parts[0]),
            let minor = Int(parts[1]),
            let patch = Int(parts[2])
        else {
            throw SvnError.parse(detail: "Unable to parse svn version: \(trimmed)")
        }

        return SvnVersion(major: major, minor: minor, patch: patch)
    }

    public static func < (lhs: SvnVersion, rhs: SvnVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }

        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }

        return lhs.patch < rhs.patch
    }
}

public struct Revision: Codable, Equatable, Hashable, Sendable, ExpressibleByIntegerLiteral, CustomStringConvertible {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public init(integerLiteral value: Int) {
        self.value = value
    }

    public var description: String {
        String(value)
    }
}

public enum ItemStatus: String, Equatable, Hashable, Sendable {
    case unversioned
    case modified
    case added
    case deleted
    case missing
    case conflicted
    case replaced
    case normal
    case ignored
    case external
    case incomplete
    case obstructed
    case none
}

public enum SvnDepth: String, Codable, Equatable, Sendable {
    case empty
    case files
    case immediates
    case infinity
}

public struct FileStatus: Equatable, Sendable {
    public let path: String
    public let itemStatus: ItemStatus
    public let revision: Revision?
    public let isTreeConflict: Bool

    public init(path: String, itemStatus: ItemStatus, revision: Revision?, isTreeConflict: Bool) {
        self.path = path
        self.itemStatus = itemStatus
        self.revision = revision
        self.isTreeConflict = isTreeConflict
    }
}

public struct BlameLine: Equatable, Sendable {
    public let lineNumber: Int
    public let revision: Revision?
    public let author: String?
    public let date: Date?

    public init(lineNumber: Int, revision: Revision?, author: String?, date: Date?) {
        self.lineNumber = lineNumber
        self.revision = revision
        self.author = author
        self.date = date
    }
}

public struct SvnProperty: Equatable, Sendable {
    public let target: String
    public let name: String
    public let value: String

    public init(target: String, name: String, value: String) {
        self.target = target
        self.name = name
        self.value = value
    }
}

public struct SvnPropertyTemplate: Equatable, Sendable {
    public let name: String
    public let defaultValue: String
    public let appliesToDirectory: Bool
    public let appliesToFile: Bool

    public init(name: String, defaultValue: String, appliesToDirectory: Bool, appliesToFile: Bool) {
        self.name = name
        self.defaultValue = defaultValue
        self.appliesToDirectory = appliesToDirectory
        self.appliesToFile = appliesToFile
    }
}

public struct MergeInfoRevisionRange: Equatable, Sendable {
    public let start: Revision
    public let end: Revision

    public init(start: Revision, end: Revision) {
        self.start = start
        self.end = end
    }

    public var revisionCount: Int {
        guard end.value >= start.value else {
            return 0
        }

        return end.value - start.value + 1
    }

    public var revisions: [Revision] {
        guard revisionCount > 0 else {
            return []
        }

        return (start.value...end.value).map { Revision($0) }
    }
}

public struct MergeInfoEntry: Equatable, Sendable {
    public let sourcePath: String
    public let ranges: [MergeInfoRevisionRange]

    public init(sourcePath: String, ranges: [MergeInfoRevisionRange]) {
        self.sourcePath = sourcePath
        self.ranges = ranges
    }

    public var revisionCount: Int {
        ranges.reduce(0) { partial, range in
            partial + range.revisionCount
        }
    }

    public var revisions: [Revision] {
        ranges.flatMap(\.revisions)
    }
}

public struct SvnLock: Equatable, Sendable {
    public let target: String
    public let token: String?
    public let owner: String?
    public let comment: String?
    public let created: Date?
    public let isOwnedByWorkingCopy: Bool
    public let isRepositoryLocked: Bool

    public init(
        target: String,
        token: String?,
        owner: String?,
        comment: String?,
        created: Date?,
        isOwnedByWorkingCopy: Bool,
        isRepositoryLocked: Bool
    ) {
        self.target = target
        self.token = token
        self.owner = owner
        self.comment = comment
        self.created = created
        self.isOwnedByWorkingCopy = isOwnedByWorkingCopy
        self.isRepositoryLocked = isRepositoryLocked
    }
}

public enum CommitGuardRuleID: String, Codable, Equatable, Hashable, Sendable {
    case conflictMarker
    case largeFile
    case deniedPath
    case suspectedSecret
}

public enum CommitGuardSeverity: String, Codable, Equatable, Sendable {
    case warning
    case blocking
}

public struct CommitGuardIssue: Equatable, Sendable {
    public let ruleID: CommitGuardRuleID
    public let severity: CommitGuardSeverity
    public let path: String
    public let message: String
    public let detail: String?

    public init(
        ruleID: CommitGuardRuleID,
        severity: CommitGuardSeverity,
        path: String,
        message: String,
        detail: String? = nil
    ) {
        self.ruleID = ruleID
        self.severity = severity
        self.path = path
        self.message = message
        self.detail = detail
    }
}

public struct CommitGuardConfiguration: Equatable, Sendable {
    public var largeFileThresholdBytes: Int
    public var deniedPathPatterns: [String]
    public var hardBlockedRules: Set<CommitGuardRuleID>

    public init(
        largeFileThresholdBytes: Int = 10 * 1024 * 1024,
        deniedPathPatterns: [String] = ["*.log", "node_modules/**", ".DS_Store"],
        hardBlockedRules: Set<CommitGuardRuleID> = []
    ) {
        self.largeFileThresholdBytes = largeFileThresholdBytes
        self.deniedPathPatterns = deniedPathPatterns
        self.hardBlockedRules = hardBlockedRules
    }
}

public struct UpdateSummary: Equatable, Sendable {
    public var added: Int
    public var updated: Int
    public var deleted: Int
    public var conflicted: Int
    public var merged: Int
    public var existed: Int
    public var replaced: Int
    public var revision: Revision?

    public init(
        added: Int = 0,
        updated: Int = 0,
        deleted: Int = 0,
        conflicted: Int = 0,
        merged: Int = 0,
        existed: Int = 0,
        replaced: Int = 0,
        revision: Revision? = nil
    ) {
        self.added = added
        self.updated = updated
        self.deleted = deleted
        self.conflicted = conflicted
        self.merged = merged
        self.existed = existed
        self.replaced = replaced
        self.revision = revision
    }
}

public struct RevisionRange: Equatable, Sendable, CustomStringConvertible {
    public let start: Revision
    public let end: Revision

    public init(start: Revision, end: Revision) {
        self.start = start
        self.end = end
    }

    public var description: String {
        "\(start):\(end)"
    }
}

public enum MergeAction: Equatable, Sendable {
    case added
    case updated
    case deleted
    case conflicted
    case merged
    case existed
    case replaced
    case unknown(Character)

    public init(rawStatus: Character) {
        switch rawStatus {
        case "A":
            self = .added
        case "U":
            self = .updated
        case "D":
            self = .deleted
        case "C":
            self = .conflicted
        case "G":
            self = .merged
        case "E":
            self = .existed
        case "R":
            self = .replaced
        default:
            self = .unknown(rawStatus)
        }
    }
}

public struct MergeAffectedPath: Equatable, Sendable {
    public let action: MergeAction
    public let path: String

    public init(action: MergeAction, path: String) {
        self.action = action
        self.path = path
    }
}

public struct MergeSummary: Equatable, Sendable {
    public var added: Int
    public var updated: Int
    public var deleted: Int
    public var conflicted: Int
    public var merged: Int
    public var existed: Int
    public var replaced: Int
    public var affectedPaths: [MergeAffectedPath]

    public init(
        added: Int = 0,
        updated: Int = 0,
        deleted: Int = 0,
        conflicted: Int = 0,
        merged: Int = 0,
        existed: Int = 0,
        replaced: Int = 0,
        affectedPaths: [MergeAffectedPath] = []
    ) {
        self.added = added
        self.updated = updated
        self.deleted = deleted
        self.conflicted = conflicted
        self.merged = merged
        self.existed = existed
        self.replaced = replaced
        self.affectedPaths = affectedPaths
    }

    public mutating func record(action: MergeAction, path: String) {
        affectedPaths.append(MergeAffectedPath(action: action, path: path))

        switch action {
        case .added:
            added += 1
        case .updated:
            updated += 1
        case .deleted:
            deleted += 1
        case .conflicted:
            conflicted += 1
        case .merged:
            merged += 1
        case .existed:
            existed += 1
        case .replaced:
            replaced += 1
        case .unknown:
            break
        }
    }
}

public enum ConflictKind: Hashable, Sendable {
    case text
    case tree
    case property
    case unknown
}

public struct TreeConflictDetails: Equatable, Sendable {
    public let operation: String?
    public let action: String?
    public let reason: String?

    public init(operation: String?, action: String?, reason: String?) {
        self.operation = operation
        self.action = action
        self.reason = reason
    }
}

public struct ConflictInfo: Equatable, Sendable {
    public let path: String
    public let kind: ConflictKind
    public let baseFile: String?
    public let mineFile: String?
    public let theirsFile: String?
    public let treeConflict: TreeConflictDetails?

    public init(
        path: String,
        kind: ConflictKind,
        baseFile: String?,
        mineFile: String?,
        theirsFile: String?,
        treeConflict: TreeConflictDetails?
    ) {
        self.path = path
        self.kind = kind
        self.baseFile = baseFile
        self.mineFile = mineFile
        self.theirsFile = theirsFile
        self.treeConflict = treeConflict
    }
}

public enum ResolveAccept: String, Equatable, Sendable {
    case working
    case mineConflict = "mine-conflict"
    case theirsConflict = "theirs-conflict"
    case mineFull = "mine-full"
    case theirsFull = "theirs-full"
}

public enum TreeConflictResolution: Equatable, Sendable {
    case keepLocal
    case acceptRemote
}

public struct Credential: Equatable, Sendable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public struct LogEntry: Equatable, Sendable {
    public let revision: Revision
    public let author: String
    public let date: Date?
    public let message: String
    public let changedPaths: [ChangedPath]

    public init(revision: Revision, author: String, date: Date?, message: String, changedPaths: [ChangedPath]) {
        self.revision = revision
        self.author = author
        self.date = date
        self.message = message
        self.changedPaths = changedPaths
    }
}

public struct ChangedPath: Equatable, Sendable {
    public let path: String
    public let action: ChangedPathAction
    public let kind: String?
    public let copyFromPath: String?
    public let copyFromRevision: Revision?

    public init(path: String, action: ChangedPathAction, kind: String?, copyFromPath: String?, copyFromRevision: Revision?) {
        self.path = path
        self.action = action
        self.kind = kind
        self.copyFromPath = copyFromPath
        self.copyFromRevision = copyFromRevision
    }
}

public enum ChangedPathAction: String, Equatable, Sendable {
    case added = "A"
    case modified = "M"
    case deleted = "D"
    case replaced = "R"
    case unknown

    public init(rawSvnAction: String?) {
        guard let rawSvnAction, let action = ChangedPathAction(rawValue: rawSvnAction) else {
            self = .unknown
            return
        }

        self = action
    }
}

public enum CommandPaletteActionID: String, Codable, Equatable, Hashable, Sendable {
    case commit
    case update
    case switchBranch
    case openWorkingCopy
}

public struct CommandPaletteAction: Equatable, Sendable {
    public let id: CommandPaletteActionID
    public let title: String
    public let keywords: [String]

    public init(id: CommandPaletteActionID, title: String, keywords: [String]) {
        self.id = id
        self.title = title
        self.keywords = keywords
    }
}

public struct CommandPaletteFileItem: Equatable, Sendable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

public enum CommandPaletteResultKind: Equatable, Sendable {
    case action(CommandPaletteActionID)
    case file(path: String)
    case log(revision: Revision)
    case aiChat(query: String)
}

public struct CommandPaletteResult: Equatable, Sendable {
    public let kind: CommandPaletteResultKind
    public let title: String
    public let subtitle: String?
    public let score: Int

    public init(kind: CommandPaletteResultKind, title: String, subtitle: String?, score: Int) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.score = score
    }
}

public enum RemoteEntryKind: Equatable, Sendable {
    case file
    case directory
    case unknown(String?)

    public init(rawSvnKind: String?) {
        switch rawSvnKind {
        case "file":
            self = .file
        case "dir":
            self = .directory
        default:
            self = .unknown(rawSvnKind)
        }
    }
}

public struct RemoteEntry: Equatable, Sendable {
    public let name: String
    public let path: String
    public let kind: RemoteEntryKind
    public let size: Int?
    public let revision: Revision?
    public let author: String?
    public let date: Date?

    public init(
        name: String,
        path: String,
        kind: RemoteEntryKind,
        size: Int?,
        revision: Revision?,
        author: String?,
        date: Date?
    ) {
        self.name = name
        self.path = path
        self.kind = kind
        self.size = size
        self.revision = revision
        self.author = author
        self.date = date
    }
}

public struct WorkingCopyRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var localPath: String
    public var repoURL: String
    public var username: String?
    public var addedAt: Date
    public var lastOpenedAt: Date
    public var isValid: Bool
    public var revision: Revision?

    public init(
        id: UUID,
        name: String,
        localPath: String,
        repoURL: String,
        username: String?,
        addedAt: Date,
        lastOpenedAt: Date,
        isValid: Bool,
        revision: Revision?
    ) {
        self.id = id
        self.name = name
        self.localPath = localPath
        self.repoURL = repoURL
        self.username = username
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
        self.isValid = isValid
        self.revision = revision
    }
}

public struct WorkspaceListFile: Codable, Equatable, Sendable {
    public var version: Int
    public var workspaces: [WorkingCopyRecord]

    public init(version: Int = 1, workspaces: [WorkingCopyRecord] = []) {
        self.version = version
        self.workspaces = workspaces
    }
}

public struct MenuBarMonitorConfiguration: Equatable, Sendable {
    public var pollIntervalMinutes: Int
    public var remoteLogBatchSize: Int

    public init(pollIntervalMinutes: Int = 10, remoteLogBatchSize: Int = 50) {
        self.pollIntervalMinutes = max(1, pollIntervalMinutes)
        self.remoteLogBatchSize = max(1, remoteLogBatchSize)
    }
}

public enum MenuBarWorkingCopySnapshotState: Equatable, Sendable {
    case loaded
    case invalidWorkingCopy
    case error(String)
}

public struct MenuBarWorkingCopySnapshot: Equatable, Sendable {
    public let recordID: UUID
    public let name: String
    public let localPath: String
    public let repoURL: String
    public let state: MenuBarWorkingCopySnapshotState
    public let localChangeCount: Int
    public let conflictedCount: Int
    public let remoteNewCommitCount: Int
    public let remoteLatestRevision: Revision?
    public let notificationSummary: String?

    public init(
        recordID: UUID,
        name: String,
        localPath: String,
        repoURL: String,
        state: MenuBarWorkingCopySnapshotState,
        localChangeCount: Int,
        conflictedCount: Int,
        remoteNewCommitCount: Int,
        remoteLatestRevision: Revision?,
        notificationSummary: String?
    ) {
        self.recordID = recordID
        self.name = name
        self.localPath = localPath
        self.repoURL = repoURL
        self.state = state
        self.localChangeCount = localChangeCount
        self.conflictedCount = conflictedCount
        self.remoteNewCommitCount = remoteNewCommitCount
        self.remoteLatestRevision = remoteLatestRevision
        self.notificationSummary = notificationSummary
    }
}

public struct MenuBarStatusSnapshot: Equatable, Sendable {
    public let checkedAt: Date
    public let workingCopies: [MenuBarWorkingCopySnapshot]

    public init(checkedAt: Date, workingCopies: [MenuBarWorkingCopySnapshot]) {
        self.checkedAt = checkedAt
        self.workingCopies = workingCopies
    }

    public var totalLocalChangeCount: Int {
        workingCopies.reduce(0) { $0 + $1.localChangeCount }
    }

    public var totalRemoteNewCommitCount: Int {
        workingCopies.reduce(0) { $0 + $1.remoteNewCommitCount }
    }

    public var hasAttentionItems: Bool {
        totalLocalChangeCount > 0 || totalRemoteNewCommitCount > 0
    }
}

public struct RepoBookmark: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var url: String
    public var username: String?
    public var addedAt: Date
    public var lastOpenedAt: Date

    public init(
        id: UUID,
        name: String,
        url: String,
        username: String?,
        addedAt: Date,
        lastOpenedAt: Date
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.username = username
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
    }
}

public struct RepoBookmarkListFile: Codable, Equatable, Sendable {
    public var version: Int
    public var bookmarks: [RepoBookmark]

    public init(version: Int = 1, bookmarks: [RepoBookmark] = []) {
        self.version = version
        self.bookmarks = bookmarks
    }
}

public enum ShelveKind: String, Codable, Equatable, Sendable {
    case manual
    case safety
}

public struct ShelveSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let wcPath: String
    public let name: String
    public let paths: [String]
    public let patchRelativePath: String
    public let createdAt: Date
    public let kind: ShelveKind

    public init(
        id: UUID,
        wcPath: String,
        name: String,
        paths: [String],
        patchRelativePath: String,
        createdAt: Date,
        kind: ShelveKind
    ) {
        self.id = id
        self.wcPath = wcPath
        self.name = name
        self.paths = paths
        self.patchRelativePath = patchRelativePath
        self.createdAt = createdAt
        self.kind = kind
    }

    public var patchFileName: String {
        URL(fileURLWithPath: patchRelativePath).lastPathComponent
    }
}

public struct ShelveListFile: Codable, Equatable, Sendable {
    public var version: Int
    public var snapshots: [ShelveSnapshot]

    public init(version: Int = 1, snapshots: [ShelveSnapshot] = []) {
        self.version = version
        self.snapshots = snapshots
    }
}

public struct SvnInfo: Equatable, Sendable {
    public let path: String
    public let url: String
    public let repositoryRoot: String?
    public let revision: Revision?
    public let kind: String?
    public let conflicts: [ConflictInfo]

    public init(
        path: String,
        url: String,
        repositoryRoot: String?,
        revision: Revision?,
        kind: String?,
        conflicts: [ConflictInfo] = []
    ) {
        self.path = path
        self.url = url
        self.repositoryRoot = repositoryRoot
        self.revision = revision
        self.kind = kind
        self.conflicts = conflicts
    }
}

public struct BranchLayout: Codable, Equatable, Sendable {
    public var trunk: String
    public var branches: String
    public var tags: String

    public init(trunk: String = "trunk", branches: String = "branches", tags: String = "tags") {
        self.trunk = trunk
        self.branches = branches
        self.tags = tags
    }
}

public enum BranchReferenceKind: Equatable, Sendable {
    case trunk
    case branch
    case tag
}

public struct BranchReference: Equatable, Sendable {
    public let name: String
    public let url: String
    public let kind: BranchReferenceKind
    public let revision: Revision?
    public let author: String?
    public let date: Date?

    public init(
        name: String,
        url: String,
        kind: BranchReferenceKind,
        revision: Revision?,
        author: String?,
        date: Date?
    ) {
        self.name = name
        self.url = url
        self.kind = kind
        self.revision = revision
        self.author = author
        self.date = date
    }
}

public struct BranchList: Equatable, Sendable {
    public var trunk: BranchReference?
    public var branches: [BranchReference]
    public var tags: [BranchReference]

    public init(
        trunk: BranchReference? = nil,
        branches: [BranchReference] = [],
        tags: [BranchReference] = []
    ) {
        self.trunk = trunk
        self.branches = branches
        self.tags = tags
    }
}

public struct ExternalDiffToolConfiguration: Codable, Equatable, Sendable {
    public var name: String
    public var executablePath: String
    public var arguments: [String]

    public init(
        name: String,
        executablePath: String,
        arguments: [String] = ["{left}", "{right}"]
    ) {
        self.name = name
        self.executablePath = executablePath
        self.arguments = arguments
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var svnPath: String?
    public var logBatchSize: Int
    public var branchLayout: BranchLayout
    public var processTimeout: TimeInterval
    public var externalDiffTool: ExternalDiffToolConfiguration?
    /// 为 true 时，提交守护将冲突标记残留等规则升级为硬阻断（不可跳过警告提交）
    public var commitGuardHardBlockConflictMarkers: Bool
    /// AI 隐私：脱敏开关与自定义规则（随设置持久化）
    public var aiPrivacy: AIPrivacySettings

    public init(
        svnPath: String? = nil,
        logBatchSize: Int = 100,
        branchLayout: BranchLayout = BranchLayout(),
        processTimeout: TimeInterval = 120,
        externalDiffTool: ExternalDiffToolConfiguration? = nil,
        commitGuardHardBlockConflictMarkers: Bool = false,
        aiPrivacy: AIPrivacySettings = AIPrivacySettings()
    ) {
        self.svnPath = svnPath
        self.logBatchSize = logBatchSize
        self.branchLayout = branchLayout
        self.processTimeout = processTimeout
        self.externalDiffTool = externalDiffTool
        self.commitGuardHardBlockConflictMarkers = commitGuardHardBlockConflictMarkers
        self.aiPrivacy = aiPrivacy
    }

    private enum CodingKeys: String, CodingKey {
        case svnPath
        case logBatchSize
        case branchLayout
        case processTimeout
        case externalDiffTool
        case commitGuardHardBlockConflictMarkers
        case aiPrivacy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        svnPath = try container.decodeIfPresent(String.self, forKey: .svnPath)
        logBatchSize = try container.decodeIfPresent(Int.self, forKey: .logBatchSize) ?? 100
        branchLayout = try container.decodeIfPresent(BranchLayout.self, forKey: .branchLayout) ?? BranchLayout()
        processTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .processTimeout) ?? 120
        externalDiffTool = try container.decodeIfPresent(ExternalDiffToolConfiguration.self, forKey: .externalDiffTool)
        commitGuardHardBlockConflictMarkers = try container.decodeIfPresent(Bool.self, forKey: .commitGuardHardBlockConflictMarkers) ?? false
        aiPrivacy = try container.decodeIfPresent(AIPrivacySettings.self, forKey: .aiPrivacy) ?? AIPrivacySettings()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(svnPath, forKey: .svnPath)
        try container.encode(logBatchSize, forKey: .logBatchSize)
        try container.encode(branchLayout, forKey: .branchLayout)
        try container.encode(processTimeout, forKey: .processTimeout)
        try container.encodeIfPresent(externalDiffTool, forKey: .externalDiffTool)
        try container.encode(commitGuardHardBlockConflictMarkers, forKey: .commitGuardHardBlockConflictMarkers)
        try container.encode(aiPrivacy, forKey: .aiPrivacy)
    }
}

public struct SettingsFile: Codable, Equatable, Sendable {
    public var version: Int
    public var settings: AppSettings

    public init(version: Int = 1, settings: AppSettings = AppSettings()) {
        self.version = version
        self.settings = settings
    }
}

public enum SvnEnvironmentStatus: Equatable, Sendable {
    case available(path: String, version: SvnVersion)
    case unsupportedVersion(path: String, version: SvnVersion, minimum: SvnVersion)
    case missing(checkedPaths: [String])
}
