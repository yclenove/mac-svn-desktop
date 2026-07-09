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

public struct SvnInfo: Equatable, Sendable {
    public let path: String
    public let url: String
    public let repositoryRoot: String?
    public let revision: Revision?
    public let kind: String?

    public init(path: String, url: String, repositoryRoot: String?, revision: Revision?, kind: String?) {
        self.path = path
        self.url = url
        self.repositoryRoot = repositoryRoot
        self.revision = revision
        self.kind = kind
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

public struct AppSettings: Codable, Equatable, Sendable {
    public var svnPath: String?
    public var logBatchSize: Int
    public var branchLayout: BranchLayout
    public var processTimeout: TimeInterval

    public init(
        svnPath: String? = nil,
        logBatchSize: Int = 100,
        branchLayout: BranchLayout = BranchLayout(),
        processTimeout: TimeInterval = 120
    ) {
        self.svnPath = svnPath
        self.logBatchSize = logBatchSize
        self.branchLayout = branchLayout
        self.processTimeout = processTimeout
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
