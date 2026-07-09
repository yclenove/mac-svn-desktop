import Foundation
import XCTest
@testable import MacSvnCore

final class TeamActivityViewModelTests: XCTestCase {
    @MainActor
    func testLoadBuildsSummaryFromLogAndLocks() async {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakeTeamActivityProvider(
            logResult: .success([
                LogEntry(
                    revision: Revision(2),
                    author: "alice",
                    date: Date(timeIntervalSince1970: 0),
                    message: "m",
                    changedPaths: [
                        ChangedPath(path: "/trunk/a.swift", action: .modified, kind: "file", copyFromPath: nil, copyFromRevision: nil)
                    ]
                )
            ]),
            lockResult: .success([
                SvnLock(
                    target: "a.swift",
                    token: nil,
                    owner: "alice",
                    comment: nil,
                    created: nil,
                    isOwnedByWorkingCopy: true,
                    isRepositoryLocked: true
                )
            ])
        )
        let viewModel = TeamActivityViewModel(workingCopy: wc, target: ".", logProvider: provider, lockProvider: provider)

        await viewModel.load(from: Revision(100), batch: 50, lockTargets: ["a.swift"])
        let logCalls = await provider.recordedLogCalls()
        let lockCalls = await provider.recordedLockCalls()

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.summary?.authorStats.map(\.author), ["alice"])
        XCTAssertEqual(viewModel.summary?.lockCards.map(\.target), ["a.swift"])
        XCTAssertEqual(logCalls, [
            TeamActivityLogCall(wc: wc, target: ".", from: Revision(100), batch: 50, verbose: true)
        ])
        XCTAssertEqual(lockCalls, [
            TeamActivityLockCall(wc: wc, targets: ["a.swift"])
        ])
    }

    @MainActor
    func testLoadFailureStoresErrorAndClearsSummary() async {
        let provider = FakeTeamActivityProvider(logResult: .failure(SvnError.network(detail: "offline")), lockResult: .success([]))
        let viewModel = TeamActivityViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: ".",
            logProvider: provider,
            lockProvider: provider
        )

        await viewModel.load(from: Revision(1), batch: 50, lockTargets: [])

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertNil(viewModel.summary)
    }
}

private struct TeamActivityLogCall: Equatable, Sendable {
    let wc: URL
    let target: String
    let from: Revision
    let batch: Int
    let verbose: Bool
}

private struct TeamActivityLockCall: Equatable, Sendable {
    let wc: URL
    let targets: [String]
}

private actor FakeTeamActivityProvider: TeamActivityLogProviding, TeamActivityLockProviding {
    private let logResult: Result<[LogEntry], Error>
    private let lockResult: Result<[SvnLock], Error>
    private var logCalls: [TeamActivityLogCall] = []
    private var lockCalls: [TeamActivityLockCall] = []

    init(logResult: Result<[LogEntry], Error>, lockResult: Result<[SvnLock], Error>) {
        self.logResult = logResult
        self.lockResult = lockResult
    }

    func recordedLogCalls() -> [TeamActivityLogCall] {
        logCalls
    }

    func recordedLockCalls() -> [TeamActivityLockCall] {
        lockCalls
    }

    func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry] {
        logCalls.append(TeamActivityLogCall(wc: wc, target: target, from: from, batch: batch, verbose: verbose))
        return try logResult.get()
    }

    func locks(wc: URL, targets: [String]) async throws -> [SvnLock] {
        lockCalls.append(TeamActivityLockCall(wc: wc, targets: targets))
        return try lockResult.get()
    }
}
