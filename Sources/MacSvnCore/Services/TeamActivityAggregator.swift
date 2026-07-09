import Foundation

public struct TeamActivityAggregator: Sendable {
    private let calendar: Calendar
    private let activePathLimit: Int

    public init(calendar: Calendar = .current, activePathLimit: Int = 10) {
        self.calendar = calendar
        self.activePathLimit = max(1, activePathLimit)
    }

    public func summarize(entries: [LogEntry], locks: [SvnLock] = []) -> TeamActivitySummary {
        TeamActivitySummary(
            dailyCommits: dailyCommits(from: entries),
            authorStats: authorStats(from: entries),
            activePaths: activePaths(from: entries),
            lockCards: lockCards(from: locks),
            revisionRange: revisionRange(from: entries)
        )
    }

    private func dailyCommits(from entries: [LogEntry]) -> [TeamActivityDay] {
        let days = entries.compactMap { entry -> Date? in
            guard let date = entry.date else {
                return nil
            }
            return calendar.startOfDay(for: date)
        }
        let counts = Dictionary(grouping: days, by: { $0 }).mapValues(\.count)

        return counts
            .map { TeamActivityDay(date: $0.key, commitCount: $0.value) }
            .sorted { $0.date < $1.date }
    }

    private func authorStats(from entries: [LogEntry]) -> [TeamActivityAuthorStat] {
        Dictionary(grouping: entries, by: \.author)
            .map { author, authorEntries in
                let latest = authorEntries.max { $0.revision.value < $1.revision.value }!
                return TeamActivityAuthorStat(
                    author: author,
                    commitCount: authorEntries.count,
                    latestRevision: latest.revision,
                    latestDate: latest.date
                )
            }
            .sorted {
                if $0.commitCount != $1.commitCount {
                    return $0.commitCount > $1.commitCount
                }
                return $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending
            }
    }

    private func activePaths(from entries: [LogEntry]) -> [TeamActivityPathStat] {
        let changedPaths = entries.flatMap { entry in
            entry.changedPaths.map { (path: $0.path, revision: entry.revision) }
        }

        return Dictionary(grouping: changedPaths, by: { $0.path })
            .map { path, changes in
                TeamActivityPathStat(
                    path: path,
                    changeCount: changes.count,
                    latestRevision: changes.map { $0.revision }.max { $0.value < $1.value }!
                )
            }
            .sorted {
                if $0.changeCount != $1.changeCount {
                    return $0.changeCount > $1.changeCount
                }
                return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
            }
            .prefix(activePathLimit)
            .map { $0 }
    }

    private func lockCards(from locks: [SvnLock]) -> [TeamActivityLockCard] {
        locks
            .map {
                TeamActivityLockCard(
                    target: $0.target,
                    owner: $0.owner,
                    comment: $0.comment,
                    created: $0.created,
                    isOwnedByWorkingCopy: $0.isOwnedByWorkingCopy,
                    isRepositoryLocked: $0.isRepositoryLocked
                )
            }
            .sorted { $0.target.localizedCaseInsensitiveCompare($1.target) == .orderedAscending }
    }

    private func revisionRange(from entries: [LogEntry]) -> RevisionRange? {
        let revisions = entries.map(\.revision.value)
        guard let min = revisions.min(), let max = revisions.max() else {
            return nil
        }
        return RevisionRange(start: Revision(min), end: Revision(max))
    }
}
