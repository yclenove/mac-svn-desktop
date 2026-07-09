import Foundation

public struct TeamActivityDay: Equatable, Sendable {
    public let date: Date
    public let commitCount: Int

    public init(date: Date, commitCount: Int) {
        self.date = date
        self.commitCount = commitCount
    }
}

public struct TeamActivityAuthorStat: Equatable, Sendable {
    public let author: String
    public let commitCount: Int
    public let latestRevision: Revision
    public let latestDate: Date?

    public init(author: String, commitCount: Int, latestRevision: Revision, latestDate: Date?) {
        self.author = author
        self.commitCount = commitCount
        self.latestRevision = latestRevision
        self.latestDate = latestDate
    }
}

public struct TeamActivityPathStat: Equatable, Sendable {
    public let path: String
    public let changeCount: Int
    public let latestRevision: Revision

    public init(path: String, changeCount: Int, latestRevision: Revision) {
        self.path = path
        self.changeCount = changeCount
        self.latestRevision = latestRevision
    }
}

public struct TeamActivityLockCard: Equatable, Sendable {
    public let target: String
    public let owner: String?
    public let comment: String?
    public let created: Date?
    public let isOwnedByWorkingCopy: Bool
    public let isRepositoryLocked: Bool

    public init(
        target: String,
        owner: String?,
        comment: String?,
        created: Date?,
        isOwnedByWorkingCopy: Bool,
        isRepositoryLocked: Bool
    ) {
        self.target = target
        self.owner = owner
        self.comment = comment
        self.created = created
        self.isOwnedByWorkingCopy = isOwnedByWorkingCopy
        self.isRepositoryLocked = isRepositoryLocked
    }
}

public struct TeamActivitySummary: Equatable, Sendable {
    public let dailyCommits: [TeamActivityDay]
    public let authorStats: [TeamActivityAuthorStat]
    public let activePaths: [TeamActivityPathStat]
    public let lockCards: [TeamActivityLockCard]
    public let revisionRange: RevisionRange?

    public init(
        dailyCommits: [TeamActivityDay],
        authorStats: [TeamActivityAuthorStat],
        activePaths: [TeamActivityPathStat],
        lockCards: [TeamActivityLockCard],
        revisionRange: RevisionRange?
    ) {
        self.dailyCommits = dailyCommits
        self.authorStats = authorStats
        self.activePaths = activePaths
        self.lockCards = lockCards
        self.revisionRange = revisionRange
    }
}
