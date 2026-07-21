import Foundation
import XCTest
@testable import MacSvnCore

final class LogStatisticsTests: XCTestCase {
    func testBuildSummarizesAuthorsDatesAndChangedPathActions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let day1 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 10)))
        let day2 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 11)))
        let entries = [
            statisticsEntry(5, author: "alice", date: day2, actions: [.modified, .added]),
            statisticsEntry(4, author: "bob", date: day1, actions: [.deleted]),
            statisticsEntry(3, author: "alice", date: day1, actions: [.replaced, .unknown])
        ]

        let statistics = LogStatisticsBuilder.build(entries: entries, calendar: calendar)

        XCTAssertEqual(statistics.totalRevisions, 3)
        XCTAssertEqual(statistics.totalAuthors, 2)
        XCTAssertEqual(statistics.totalChangedPaths, 5)
        XCTAssertEqual(statistics.firstDate, day1)
        XCTAssertEqual(statistics.lastDate, day2)
        XCTAssertEqual(statistics.calendarDays, 2)
        XCTAssertEqual(statistics.activeDays, 2)
        XCTAssertEqual(statistics.averageCommitsPerDay, 1.5, accuracy: 0.001)
        XCTAssertEqual(statistics.averageCommitsPerWeek, 10.5, accuracy: 0.001)
        XCTAssertEqual(statistics.authors, [
            LogAuthorStatistics(author: "alice", commits: 2, percentage: 2.0 / 3.0),
            LogAuthorStatistics(author: "bob", commits: 1, percentage: 1.0 / 3.0)
        ])
        XCTAssertEqual(statistics.activity.map(\.commits), [2, 1])
        XCTAssertEqual(statistics.actions, [
            LogActionStatistics(action: .added, count: 1),
            LogActionStatistics(action: .modified, count: 1),
            LogActionStatistics(action: .deleted, count: 1),
            LogActionStatistics(action: .replaced, count: 1),
            LogActionStatistics(action: .unknown, count: 1)
        ])
    }

    func testBuildHandlesEmptyAndUnknownAuthorsWithoutInvalidAverages() {
        XCTAssertEqual(LogStatisticsBuilder.build(entries: []), .empty)

        let statistics = LogStatisticsBuilder.build(entries: [
            statisticsEntry(1, author: "", date: nil, actions: [])
        ])

        XCTAssertEqual(statistics.totalAuthors, 1)
        XCTAssertEqual(statistics.authors.first?.author, "unknown")
        XCTAssertEqual(statistics.calendarDays, 0)
        XCTAssertEqual(statistics.averageCommitsPerDay, 0)
        XCTAssertEqual(statistics.averageCommitsPerWeek, 0)
    }
}

private func statisticsEntry(
    _ revision: Int,
    author: String,
    date: Date?,
    actions: [ChangedPathAction]
) -> LogEntry {
    LogEntry(
        revision: Revision(revision),
        author: author,
        date: date,
        message: "r\(revision)",
        changedPaths: actions.enumerated().map { index, action in
            ChangedPath(
                path: "/file-\(revision)-\(index)",
                action: action,
                kind: "file",
                copyFromPath: nil,
                copyFromRevision: nil
            )
        }
    )
}
