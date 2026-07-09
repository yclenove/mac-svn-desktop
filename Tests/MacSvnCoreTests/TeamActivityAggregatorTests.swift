import Foundation
import XCTest
@testable import MacSvnCore

final class TeamActivityAggregatorTests: XCTestCase {
    func testSummarizeBuildsHeatmapAuthorRankingActivePathsAndLockBoard() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let aggregator = TeamActivityAggregator(calendar: calendar, activePathLimit: 2)
        let entries = [
            logEntry(
                revision: 12,
                author: "alice",
                date: Date(timeIntervalSince1970: 86_400),
                paths: ["/trunk/login/LoginView.swift", "/trunk/payment/Pay.swift"]
            ),
            logEntry(
                revision: 11,
                author: "bob",
                date: Date(timeIntervalSince1970: 86_400 + 3_600),
                paths: ["/trunk/login/LoginView.swift"]
            ),
            logEntry(
                revision: 10,
                author: "alice",
                date: Date(timeIntervalSince1970: 0),
                paths: ["/trunk/login/LoginView.swift"]
            )
        ]
        let locks = [
            SvnLock(
                target: "zeta.txt",
                token: nil,
                owner: "bob",
                comment: "editing",
                created: Date(timeIntervalSince1970: 10),
                isOwnedByWorkingCopy: false,
                isRepositoryLocked: true
            ),
            SvnLock(
                target: "alpha.txt",
                token: "t",
                owner: "alice",
                comment: nil,
                created: nil,
                isOwnedByWorkingCopy: true,
                isRepositoryLocked: true
            )
        ]

        let summary = aggregator.summarize(entries: entries, locks: locks)

        XCTAssertEqual(summary.revisionRange, RevisionRange(start: Revision(10), end: Revision(12)))
        XCTAssertEqual(summary.dailyCommits.map(\.commitCount), [1, 2])
        XCTAssertEqual(summary.authorStats.map(\.author), ["alice", "bob"])
        XCTAssertEqual(summary.authorStats.map(\.commitCount), [2, 1])
        XCTAssertEqual(summary.authorStats.first?.latestRevision, Revision(12))
        XCTAssertEqual(summary.activePaths.map(\.path), ["/trunk/login/LoginView.swift", "/trunk/payment/Pay.swift"])
        XCTAssertEqual(summary.activePaths.map(\.changeCount), [3, 1])
        XCTAssertEqual(summary.lockCards.map(\.target), ["alpha.txt", "zeta.txt"])
        XCTAssertEqual(summary.lockCards.first?.owner, "alice")
    }

    private func logEntry(revision: Int, author: String, date: Date, paths: [String]) -> LogEntry {
        LogEntry(
            revision: Revision(revision),
            author: author,
            date: date,
            message: "r\(revision)",
            changedPaths: paths.map {
                ChangedPath(path: $0, action: .modified, kind: "file", copyFromPath: nil, copyFromRevision: nil)
            }
        )
    }
}
