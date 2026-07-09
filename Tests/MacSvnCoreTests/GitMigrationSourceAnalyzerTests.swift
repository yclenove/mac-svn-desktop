import Foundation
import XCTest
@testable import MacSvnCore

final class GitMigrationSourceAnalyzerTests: XCTestCase {
    func testAnalyzeDetectsStandardLayoutAuthorsAndRevisionRange() async throws {
        let environment = GitMigrationEnvironmentStatus(
            git: GitMigrationToolStatus(isAvailable: true, versionOutput: "git version 2.45.0", errorSummary: nil),
            gitSvn: GitMigrationToolStatus(isAvailable: true, versionOutput: "git-svn version 2.45.0", errorSummary: nil)
        )
        let environmentChecker = FakeGitMigrationEnvironmentChecker(result: .success(environment))
        let sourceProvider = FakeGitMigrationSourceProvider(
            entries: [
                remoteDirectory("branches"),
                remoteDirectory("tags"),
                remoteDirectory("trunk"),
                RemoteEntry(name: "README.txt", path: "README.txt", kind: .file, size: 10, revision: nil, author: nil, date: nil)
            ],
            logEntries: [
                logEntry(revision: Revision(9), author: "zhangsan"),
                logEntry(revision: Revision(3), author: "lisi"),
                logEntry(revision: Revision(1), author: "zhangsan")
            ]
        )
        let analyzer = GitMigrationSourceAnalyzer(
            environmentChecker: environmentChecker,
            listProvider: sourceProvider,
            logProvider: sourceProvider
        )
        let auth = Credential(username: "u", password: "p")

        let analysis = try await analyzer.analyze(repositoryRoot: "file:///repo", auth: auth)

        XCTAssertEqual(analysis, GitMigrationSourceAnalysis(
            repositoryRoot: "file:///repo",
            environment: environment,
            layout: GitMigrationRepositoryLayout(
                kind: .standard,
                trunkPath: "trunk",
                branchesPath: "branches",
                tagsPath: "tags",
                confidence: 1.0
            ),
            authors: [
                GitMigrationAuthor(svnUsername: "lisi"),
                GitMigrationAuthor(svnUsername: "zhangsan")
            ],
            latestRevision: Revision(9),
            oldestRevision: Revision(1),
            totalRevisionCount: 3
        ))
        let checkCallCount = await environmentChecker.checkCallCount()
        let recordedListCalls = await sourceProvider.recordedListCalls()
        let recordedLogCalls = await sourceProvider.recordedLogCalls()
        XCTAssertEqual(checkCallCount, 1)
        XCTAssertEqual(recordedListCalls, [
            SourceListCall(url: "file:///repo", depth: .immediates, auth: auth)
        ])
        XCTAssertEqual(recordedLogCalls, [
            SourceLogCall(url: "file:///repo", batch: Int.max, verbose: false, auth: auth)
        ])
    }

    func testAnalyzeTrimsRepositoryRootAndRejectsEmptyURLBeforeCallingProviders() async {
        let environmentChecker = FakeGitMigrationEnvironmentChecker(result: .success(.missing))
        let sourceProvider = FakeGitMigrationSourceProvider(entries: [], logEntries: [])
        let analyzer = GitMigrationSourceAnalyzer(
            environmentChecker: environmentChecker,
            listProvider: sourceProvider,
            logProvider: sourceProvider
        )

        do {
            _ = try await analyzer.analyze(repositoryRoot: "  ", auth: nil)
            XCTFail("Expected empty repository root")
        } catch let error as GitMigrationSourceAnalysisError {
            XCTAssertEqual(error, .emptyRepositoryRoot)
        } catch {
            XCTFail("Expected GitMigrationSourceAnalysisError, got \(error)")
        }

        let checkCallCount = await environmentChecker.checkCallCount()
        let recordedListCalls = await sourceProvider.recordedListCalls()
        let recordedLogCalls = await sourceProvider.recordedLogCalls()
        XCTAssertEqual(checkCallCount, 0)
        XCTAssertTrue(recordedListCalls.isEmpty)
        XCTAssertTrue(recordedLogCalls.isEmpty)
    }

    func testAnalyzeReportsCustomLayoutWhenStandardDirectoriesAreMissing() async throws {
        let environmentChecker = FakeGitMigrationEnvironmentChecker(result: .success(.missing))
        let sourceProvider = FakeGitMigrationSourceProvider(
            entries: [
                remoteDirectory("main"),
                remoteDirectory("dev")
            ],
            logEntries: [
                logEntry(revision: Revision(4), author: "alice")
            ]
        )
        let analyzer = GitMigrationSourceAnalyzer(
            environmentChecker: environmentChecker,
            listProvider: sourceProvider,
            logProvider: sourceProvider
        )

        let analysis = try await analyzer.analyze(repositoryRoot: " file:///repo ", auth: nil)

        XCTAssertEqual(analysis.repositoryRoot, "file:///repo")
        XCTAssertEqual(analysis.layout.kind, .custom)
        XCTAssertEqual(analysis.layout.confidence, 0)
        XCTAssertEqual(analysis.authors, [GitMigrationAuthor(svnUsername: "alice")])
    }
}

private struct SourceListCall: Equatable, Sendable {
    let url: String
    let depth: SvnDepth
    let auth: Credential?
}

private struct SourceLogCall: Equatable, Sendable {
    let url: String
    let batch: Int
    let verbose: Bool
    let auth: Credential?
}

private actor FakeGitMigrationEnvironmentChecker: GitMigrationEnvironmentChecking {
    private let result: Result<GitMigrationEnvironmentStatus, Error>
    private var calls = 0

    init(result: Result<GitMigrationEnvironmentStatus, Error>) {
        self.result = result
    }

    func check() async throws -> GitMigrationEnvironmentStatus {
        calls += 1
        return try result.get()
    }

    func checkCallCount() -> Int {
        calls
    }
}

private actor FakeGitMigrationSourceProvider: GitMigrationSourceListing, GitMigrationSourceLogging {
    private let entries: [RemoteEntry]
    private let logEntries: [LogEntry]
    private var listCalls: [SourceListCall] = []
    private var logCalls: [SourceLogCall] = []

    init(entries: [RemoteEntry], logEntries: [LogEntry]) {
        self.entries = entries
        self.logEntries = logEntries
    }

    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry] {
        listCalls.append(SourceListCall(url: url, depth: depth, auth: auth))
        return entries
    }

    func remoteLogFromHead(url: String, batch: Int, verbose: Bool, auth: Credential?) async throws -> [LogEntry] {
        logCalls.append(SourceLogCall(url: url, batch: batch, verbose: verbose, auth: auth))
        return logEntries
    }

    func recordedListCalls() -> [SourceListCall] {
        listCalls
    }

    func recordedLogCalls() -> [SourceLogCall] {
        logCalls
    }
}

private func remoteDirectory(_ name: String) -> RemoteEntry {
    RemoteEntry(name: name, path: name, kind: .directory, size: nil, revision: nil, author: nil, date: nil)
}

private func logEntry(revision: Revision, author: String) -> LogEntry {
    LogEntry(revision: revision, author: author, date: nil, message: "", changedPaths: [])
}

private extension GitMigrationEnvironmentStatus {
    static let missing = GitMigrationEnvironmentStatus(
        git: GitMigrationToolStatus(isAvailable: false, versionOutput: nil, errorSummary: "missing"),
        gitSvn: GitMigrationToolStatus(isAvailable: false, versionOutput: nil, errorSummary: "missing")
    )
}
