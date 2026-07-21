import Foundation

public struct LogAuthorStatistics: Equatable, Sendable {
    public let author: String
    public let commits: Int
    public let percentage: Double

    public init(author: String, commits: Int, percentage: Double) {
        self.author = author
        self.commits = commits
        self.percentage = percentage
    }
}

public struct LogActivityStatistics: Equatable, Sendable {
    public let date: Date
    public let commits: Int

    public init(date: Date, commits: Int) {
        self.date = date
        self.commits = commits
    }
}

public struct LogActionStatistics: Equatable, Sendable {
    public let action: ChangedPathAction
    public let count: Int

    public init(action: ChangedPathAction, count: Int) {
        self.action = action
        self.count = count
    }
}

public struct LogStatistics: Equatable, Sendable {
    public let totalRevisions: Int
    public let totalAuthors: Int
    public let totalChangedPaths: Int
    public let firstDate: Date?
    public let lastDate: Date?
    public let calendarDays: Int
    public let activeDays: Int
    public let averageCommitsPerDay: Double
    public let averageCommitsPerWeek: Double
    public let authors: [LogAuthorStatistics]
    public let activity: [LogActivityStatistics]
    public let actions: [LogActionStatistics]

    public init(
        totalRevisions: Int,
        totalAuthors: Int,
        totalChangedPaths: Int,
        firstDate: Date?,
        lastDate: Date?,
        calendarDays: Int,
        activeDays: Int,
        averageCommitsPerDay: Double,
        averageCommitsPerWeek: Double,
        authors: [LogAuthorStatistics],
        activity: [LogActivityStatistics],
        actions: [LogActionStatistics]
    ) {
        self.totalRevisions = totalRevisions
        self.totalAuthors = totalAuthors
        self.totalChangedPaths = totalChangedPaths
        self.firstDate = firstDate
        self.lastDate = lastDate
        self.calendarDays = calendarDays
        self.activeDays = activeDays
        self.averageCommitsPerDay = averageCommitsPerDay
        self.averageCommitsPerWeek = averageCommitsPerWeek
        self.authors = authors
        self.activity = activity
        self.actions = actions
    }

    public static let empty = LogStatistics(
        totalRevisions: 0,
        totalAuthors: 0,
        totalChangedPaths: 0,
        firstDate: nil,
        lastDate: nil,
        calendarDays: 0,
        activeDays: 0,
        averageCommitsPerDay: 0,
        averageCommitsPerWeek: 0,
        authors: [],
        activity: [],
        actions: []
    )
}

public enum LogStatisticsBuilder: Sendable {
    public static func build(
        entries: [LogEntry],
        calendar: Calendar = .current
    ) -> LogStatistics {
        guard !entries.isEmpty else { return .empty }

        var authorCounts: [String: Int] = [:]
        var activityCounts: [Date: Int] = [:]
        var actionCounts: [ChangedPathAction: Int] = [:]
        let datedEntries = entries.compactMap { entry -> Date? in
            let author = entry.author.trimmingCharacters(in: .whitespacesAndNewlines)
            authorCounts[author.isEmpty ? "unknown" : author, default: 0] += 1
            for changedPath in entry.changedPaths {
                actionCounts[changedPath.action, default: 0] += 1
            }
            guard let date = entry.date else { return nil }
            activityCounts[calendar.startOfDay(for: date), default: 0] += 1
            return date
        }

        let firstDate = datedEntries.min()
        let lastDate = datedEntries.max()
        let calendarDays: Int
        if let firstDate, let lastDate {
            calendarDays = max(
                1,
                (calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: firstDate),
                    to: calendar.startOfDay(for: lastDate)
                ).day ?? 0) + 1
            )
        } else {
            calendarDays = 0
        }
        let averagePerDay = calendarDays > 0
            ? Double(entries.count) / Double(calendarDays)
            : 0

        var authors: [LogAuthorStatistics] = []
        for (author, count) in authorCounts {
            authors.append(LogAuthorStatistics(
                author: author,
                commits: count,
                percentage: Double(count) / Double(entries.count)
            ))
        }
        authors.sort { lhs, rhs in
            if lhs.commits != rhs.commits { return lhs.commits > rhs.commits }
            return lhs.author.localizedCaseInsensitiveCompare(rhs.author) == .orderedAscending
        }

        let activity = activityCounts.map { date, count in
            LogActivityStatistics(date: date, commits: count)
        }.sorted { $0.date < $1.date }

        let actionOrder: [ChangedPathAction] = [.added, .modified, .deleted, .replaced, .unknown]
        var actions: [LogActionStatistics] = []
        for action in actionOrder {
            if let count = actionCounts[action], count > 0 {
                actions.append(LogActionStatistics(action: action, count: count))
            }
        }

        return LogStatistics(
            totalRevisions: entries.count,
            totalAuthors: authorCounts.count,
            totalChangedPaths: entries.reduce(0) { $0 + $1.changedPaths.count },
            firstDate: firstDate,
            lastDate: lastDate,
            calendarDays: calendarDays,
            activeDays: activity.count,
            averageCommitsPerDay: averagePerDay,
            averageCommitsPerWeek: averagePerDay * 7,
            authors: authors,
            activity: activity,
            actions: actions
        )
    }
}
