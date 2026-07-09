import Foundation
import XCTest
@testable import MacSvnCore

final class MenuBarStatusSnapshotterTests: XCTestCase {
    func testSnapshotCountsLocalChangesRemoteCommitsAndBuildsNotificationSummary() async throws {
        let now = Date(timeIntervalSince1970: 1_800)
        let record = WorkingCopyRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "ProjectA",
            localPath: "/tmp/ProjectA",
            repoURL: "https://svn.example.com/repo/trunk",
            username: "yangchao",
            addedAt: Date(timeIntervalSince1970: 1_000),
            lastOpenedAt: Date(timeIntervalSince1970: 1_200),
            isValid: true,
            revision: Revision(100)
        )
        let statusProvider = FakeMenuBarStatusProvider(statuses: [
            URL(fileURLWithPath: "/tmp/ProjectA"): [
                FileStatus(path: "README.md", itemStatus: .modified, revision: Revision(100), isTreeConflict: false),
                FileStatus(path: "Sources/App.swift", itemStatus: .normal, revision: Revision(100), isTreeConflict: false),
                FileStatus(path: "conflicted.txt", itemStatus: .conflicted, revision: Revision(100), isTreeConflict: true)
            ]
        ])
        let remoteLogProvider = FakeMenuBarRemoteLogProvider(entries: [
            "https://svn.example.com/repo/trunk": [
                LogEntry(revision: Revision(103), author: "alice", date: nil, message: "修复支付回调", changedPaths: []),
                LogEntry(revision: Revision(102), author: "bob", date: nil, message: "补充登录重试", changedPaths: []),
                LogEntry(revision: Revision(100), author: "root", date: nil, message: "baseline", changedPaths: [])
            ]
        ])
        let snapshotter = MenuBarStatusSnapshotter(
            statusProvider: statusProvider,
            remoteLogProvider: remoteLogProvider,
            configuration: MenuBarMonitorConfiguration(remoteLogBatchSize: 10)
        )

        let snapshot = try await snapshotter.snapshot(records: [record], now: now)

        XCTAssertEqual(snapshot.checkedAt, now)
        XCTAssertEqual(snapshot.totalLocalChangeCount, 2)
        XCTAssertEqual(snapshot.totalRemoteNewCommitCount, 2)
        XCTAssertTrue(snapshot.hasAttentionItems)
        XCTAssertEqual(snapshot.workingCopies.count, 1)
        XCTAssertEqual(snapshot.workingCopies[0].recordID, record.id)
        XCTAssertEqual(snapshot.workingCopies[0].name, "ProjectA")
        XCTAssertEqual(snapshot.workingCopies[0].state, .loaded)
        XCTAssertEqual(snapshot.workingCopies[0].localChangeCount, 2)
        XCTAssertEqual(snapshot.workingCopies[0].conflictedCount, 1)
        XCTAssertEqual(snapshot.workingCopies[0].remoteNewCommitCount, 2)
        XCTAssertEqual(snapshot.workingCopies[0].remoteLatestRevision, Revision(103))
        XCTAssertEqual(snapshot.workingCopies[0].notificationSummary, "ProjectA 有 2 个新提交（alice: 修复支付回调）")

        let statusCalls = await statusProvider.recordedCalls()
        let remoteLogCalls = await remoteLogProvider.recordedCalls()
        XCTAssertEqual(statusCalls, [URL(fileURLWithPath: "/tmp/ProjectA")])
        XCTAssertEqual(remoteLogCalls, [
            RemoteLogCall(url: "https://svn.example.com/repo/trunk", batch: 10, verbose: false, auth: nil)
        ])
    }
}

private struct RemoteLogCall: Equatable, Sendable {
    let url: String
    let batch: Int
    let verbose: Bool
    let auth: Credential?
}

private actor FakeMenuBarStatusProvider: StatusProviding {
    private let statuses: [URL: [FileStatus]]
    private var calls: [URL] = []

    init(statuses: [URL: [FileStatus]]) {
        self.statuses = statuses
    }

    func recordedCalls() -> [URL] {
        calls
    }

    func status(wc: URL) async throws -> [FileStatus] {
        calls.append(wc)
        return statuses[wc] ?? []
    }
}

private actor FakeMenuBarRemoteLogProvider: MenuBarRemoteLogProviding {
    private let entries: [String: [LogEntry]]
    private var calls: [RemoteLogCall] = []

    init(entries: [String: [LogEntry]]) {
        self.entries = entries
    }

    func recordedCalls() -> [RemoteLogCall] {
        calls
    }

    func remoteLogFromHead(url: String, batch: Int, verbose: Bool, auth: Credential?) async throws -> [LogEntry] {
        calls.append(RemoteLogCall(url: url, batch: batch, verbose: verbose, auth: auth))
        return entries[url] ?? []
    }
}
