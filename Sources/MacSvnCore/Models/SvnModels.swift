import Foundation

public struct SvnVersion: Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }
}

public struct Revision: Equatable, Hashable, Sendable, ExpressibleByIntegerLiteral, CustomStringConvertible {
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

public enum ItemStatus: String, Equatable, Sendable {
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
