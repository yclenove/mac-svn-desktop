import Foundation
import XCTest
@testable import MacSvnCore

final class CommitViewModelTests: XCTestCase {
    func testCommitCandidatesIncludeVersionedChangesAndConflictsOnly() {
        let candidates = CommitSelectionPolicy.candidates(from: sampleStatuses())

        XCTAssertEqual(candidates.map(\.path), [
            "modified.swift",
            "added.swift",
            "deleted.swift",
            "replaced.swift",
            "conflict.swift",
            "tree-conflict.swift"
        ])
    }

    func testDefaultSelectionExcludesConflictsAndUnsupportedStatuses() {
        let selected = CommitSelectionPolicy.defaultSelectedPaths(from: sampleStatuses())

        XCTAssertEqual(selected, Set([
            "modified.swift",
            "added.swift",
            "deleted.swift",
            "replaced.swift"
        ]))
    }

    @MainActor
    func testCommitUsesSelectedPathsMessageAuthAndRefreshesStatuses() async {
        let commitProvider = FakeCommitProvider(result: .success(Revision(42)))
        let statusProvider = FakeStatusProvider(result: .success([
            FileStatus(path: "remaining.swift", itemStatus: .modified, revision: Revision(42), isTreeConflict: false)
        ]))
        let viewModel = CommitViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            statuses: sampleStatuses(),
            commitProvider: commitProvider,
            statusProvider: statusProvider
        )
        viewModel.message = "修复：登录超时"
        viewModel.setSelected(false, for: "deleted.swift")

        await viewModel.commit(auth: Credential(username: "u", password: "p"))
        let commitCalls = await commitProvider.recordedCalls()
        let statusRequests = await statusProvider.requestedWorkingCopies()

        XCTAssertEqual(viewModel.state, .committed(Revision(42)))
        XCTAssertEqual(viewModel.committedRevision, Revision(42))
        XCTAssertEqual(viewModel.refreshedStatuses.map(\.path), ["remaining.swift"])
        XCTAssertEqual(commitCalls, [
            CommitCall(
                wc: URL(fileURLWithPath: "/tmp/wc"),
                paths: ["modified.swift", "added.swift", "replaced.swift"],
                message: "修复：登录超时",
                auth: Credential(username: "u", password: "p"),
                skipGuardWarnings: false
            )
        ])
        XCTAssertEqual(statusRequests, [URL(fileURLWithPath: "/tmp/wc")])
    }

    @MainActor
    func testCommitRejectsEmptyMessageBeforeCallingProvider() async {
        let commitProvider = FakeCommitProvider(result: .success(Revision(42)))
        let statusProvider = FakeStatusProvider(result: .success([]))
        let viewModel = CommitViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            statuses: sampleStatuses(),
            commitProvider: commitProvider,
            statusProvider: statusProvider
        )
        viewModel.message = "   "

        await viewModel.commit(auth: nil)
        let commitCalls = await commitProvider.recordedCalls()

        XCTAssertEqual(viewModel.state, .error("emptyCommitMessage"))
        XCTAssertTrue(commitCalls.isEmpty)
    }

    @MainActor
    func testCommitRejectsEmptySelectionBeforeCallingProvider() async {
        let commitProvider = FakeCommitProvider(result: .success(Revision(42)))
        let statusProvider = FakeStatusProvider(result: .success([]))
        let viewModel = CommitViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            statuses: sampleStatuses(),
            commitProvider: commitProvider,
            statusProvider: statusProvider
        )
        viewModel.message = "fix"
        viewModel.selectedPaths.removeAll()

        await viewModel.commit(auth: nil)
        let commitCalls = await commitProvider.recordedCalls()

        XCTAssertEqual(viewModel.state, .error("noSelectedPaths"))
        XCTAssertTrue(commitCalls.isEmpty)
    }

    @MainActor
    func testCommitGuardWarningsStoreConfirmationStateBeforeRetry() async {
        let issue = CommitGuardIssue(
            ruleID: .largeFile,
            severity: .warning,
            path: "big.bin",
            message: "Large file.",
            detail: nil
        )
        let commitProvider = FakeCommitProvider(results: [
            .failure(SvnServiceError.commitGuardWarnings([issue])),
            .success(Revision(42))
        ])
        let statusProvider = FakeStatusProvider(result: .success([]))
        let viewModel = CommitViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            statuses: sampleStatuses(),
            commitProvider: commitProvider,
            statusProvider: statusProvider
        )
        viewModel.message = "fix"

        await viewModel.commit(auth: nil)

        XCTAssertEqual(viewModel.state, .guardWarnings([issue]))
        XCTAssertEqual(viewModel.guardIssues, [issue])

        await viewModel.commit(auth: nil, skipGuardWarnings: true)
        let skipFlags = await commitProvider.recordedCalls().map(\.skipGuardWarnings)

        XCTAssertEqual(viewModel.state, .committed(Revision(42)))
        XCTAssertEqual(skipFlags, [false, true])
    }

    @MainActor
    func testGenerateAICommitMessageFillsMessageWithoutCommitting() async {
        let draft = AICommitMessageDraft(
            message: "feat: 增加登录校验",
            providerID: UUID(),
            sourceFileCount: 1,
            redactionMatches: [],
            promptCount: 1,
            usedMapReduce: false
        )
        let commitProvider = FakeCommitProvider(result: .success(Revision(42)))
        let generator = FakeAICommitMessageGenerator(result: .success(draft))
        let viewModel = CommitViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            statuses: sampleStatuses(),
            commitProvider: commitProvider,
            statusProvider: FakeStatusProvider(result: .success([])),
            aiCommitMessageGenerator: generator
        )
        viewModel.setSelected(false, for: "deleted.swift")

        await viewModel.generateAICommitMessage(format: .conventionalChinese)
        let calls = await generator.recordedCalls()
        let commitCalls = await commitProvider.recordedCalls()

        XCTAssertEqual(viewModel.message, "feat: 增加登录校验")
        XCTAssertEqual(viewModel.aiCommitMessageDraft, draft)
        XCTAssertEqual(viewModel.aiCommitMessageState, .generated(draft))
        XCTAssertEqual(calls.map(\.paths), [["modified.swift", "added.swift", "replaced.swift"]])
        XCTAssertTrue(commitCalls.isEmpty)
    }

    @MainActor
    func testGenerateAICommitMessageStoresUnavailableAndSelectionErrors() async {
        let noGeneratorViewModel = CommitViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            statuses: sampleStatuses(),
            commitProvider: FakeCommitProvider(result: .success(Revision(42))),
            statusProvider: FakeStatusProvider(result: .success([]))
        )

        await noGeneratorViewModel.generateAICommitMessage()

        XCTAssertEqual(noGeneratorViewModel.aiCommitMessageState, .error("aiCommitMessageGeneratorUnavailable"))

        let generator = FakeAICommitMessageGenerator(result: .failure(AICommitMessageError.emptySelection))
        let emptySelectionViewModel = CommitViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            statuses: sampleStatuses(),
            commitProvider: FakeCommitProvider(result: .success(Revision(42))),
            statusProvider: FakeStatusProvider(result: .success([])),
            aiCommitMessageGenerator: generator
        )
        emptySelectionViewModel.selectedPaths.removeAll()

        await emptySelectionViewModel.generateAICommitMessage()

        XCTAssertEqual(
            emptySelectionViewModel.aiCommitMessageState,
            .error(String(describing: AICommitMessageError.emptySelection))
        )
    }

    @MainActor
    func testRunAIPreCommitReviewStoresResultWithoutCommittingOrBlocking() async {
        let result = AIPreCommitReviewResult(
            summary: "发现 1 条阻断建议",
            findings: [
                AIPreCommitReviewFinding(
                    severity: .blockingSuggestion,
                    category: .correctness,
                    path: "modified.swift",
                    line: 12,
                    message: "可能空指针。",
                    rationale: "AI 建议人工检查。"
                )
            ],
            providerID: UUID(),
            sourceFileCount: 1,
            redactionMatches: [],
            promptCount: 1,
            usedMapReduce: false
        )
        let commitProvider = FakeCommitProvider(result: .success(Revision(42)))
        let reviewer = FakeAIPreCommitReviewer(result: .success(result))
        let viewModel = CommitViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            statuses: sampleStatuses(),
            commitProvider: commitProvider,
            statusProvider: FakeStatusProvider(result: .success([])),
            aiPreCommitReviewer: reviewer
        )
        viewModel.message = "fix"
        viewModel.setSelected(false, for: "deleted.swift")

        await viewModel.runAIPreCommitReview()
        let reviewCalls = await reviewer.recordedCalls()
        let commitCallsBeforeCommit = await commitProvider.recordedCalls()

        XCTAssertEqual(viewModel.aiPreCommitReviewResult, result)
        XCTAssertEqual(viewModel.aiPreCommitReviewState, .reviewed(result))
        XCTAssertEqual(reviewCalls.map(\.paths), [["modified.swift", "added.swift", "replaced.swift"]])
        XCTAssertTrue(commitCallsBeforeCommit.isEmpty)
        XCTAssertTrue(viewModel.canCommit)

        await viewModel.commit(auth: nil)
        let commitCallsAfterCommit = await commitProvider.recordedCalls()

        XCTAssertEqual(commitCallsAfterCommit.count, 1)
    }

    @MainActor
    func testRunAIPreCommitReviewStoresUnavailableAndSelectionErrors() async {
        let noReviewerViewModel = CommitViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            statuses: sampleStatuses(),
            commitProvider: FakeCommitProvider(result: .success(Revision(42))),
            statusProvider: FakeStatusProvider(result: .success([]))
        )

        await noReviewerViewModel.runAIPreCommitReview()

        XCTAssertEqual(noReviewerViewModel.aiPreCommitReviewState, .error("aiPreCommitReviewerUnavailable"))

        let reviewer = FakeAIPreCommitReviewer(result: .failure(AIPreCommitReviewError.emptySelection))
        let emptySelectionViewModel = CommitViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            statuses: sampleStatuses(),
            commitProvider: FakeCommitProvider(result: .success(Revision(42))),
            statusProvider: FakeStatusProvider(result: .success([])),
            aiPreCommitReviewer: reviewer
        )
        emptySelectionViewModel.selectedPaths.removeAll()

        await emptySelectionViewModel.runAIPreCommitReview()

        XCTAssertEqual(
            emptySelectionViewModel.aiPreCommitReviewState,
            .error(String(describing: AIPreCommitReviewError.emptySelection))
        )
    }

    private func sampleStatuses() -> [FileStatus] {
        [
            FileStatus(path: "modified.swift", itemStatus: .modified, revision: Revision(1), isTreeConflict: false),
            FileStatus(path: "added.swift", itemStatus: .added, revision: Revision(1), isTreeConflict: false),
            FileStatus(path: "deleted.swift", itemStatus: .deleted, revision: Revision(1), isTreeConflict: false),
            FileStatus(path: "replaced.swift", itemStatus: .replaced, revision: Revision(1), isTreeConflict: false),
            FileStatus(path: "conflict.swift", itemStatus: .conflicted, revision: Revision(1), isTreeConflict: false),
            FileStatus(path: "tree-conflict.swift", itemStatus: .modified, revision: Revision(1), isTreeConflict: true),
            FileStatus(path: "scratch.tmp", itemStatus: .unversioned, revision: nil, isTreeConflict: false),
            FileStatus(path: "ignored.log", itemStatus: .ignored, revision: nil, isTreeConflict: false),
            FileStatus(path: "missing.swift", itemStatus: .missing, revision: Revision(1), isTreeConflict: false),
            FileStatus(path: "normal.swift", itemStatus: .normal, revision: Revision(1), isTreeConflict: false)
        ]
    }
}

private struct CommitCall: Equatable, Sendable {
    let wc: URL
    let paths: [String]
    let message: String
    let auth: Credential?
    let skipGuardWarnings: Bool
}

private actor FakeCommitProvider: CommitProviding {
    private var results: [Result<Revision, Error>]
    private var calls: [CommitCall] = []

    init(result: Result<Revision, Error>) {
        self.results = [result]
    }

    init(results: [Result<Revision, Error>]) {
        self.results = results
    }

    func recordedCalls() -> [CommitCall] {
        calls
    }

    func commit(
        wc: URL,
        paths: [String],
        message: String,
        auth: Credential?,
        skipGuardWarnings: Bool
    ) async throws -> Revision {
        calls.append(CommitCall(
            wc: wc,
            paths: paths,
            message: message,
            auth: auth,
            skipGuardWarnings: skipGuardWarnings
        ))
        guard !results.isEmpty else {
            return Revision(0)
        }
        return try results.removeFirst().get()
    }
}

private actor FakeStatusProvider: StatusProviding {
    private let result: Result<[FileStatus], Error>
    private var requests: [URL] = []

    init(result: Result<[FileStatus], Error>) {
        self.result = result
    }

    func requestedWorkingCopies() -> [URL] {
        requests
    }

    func status(wc: URL) async throws -> [FileStatus] {
        requests.append(wc)
        return try result.get()
    }
}

private struct AIPreCommitReviewCall: Equatable, Sendable {
    let wc: URL
    let paths: [String]
    let privacySettings: AIPrivacySettings
}

private actor FakeAIPreCommitReviewer: AIPreCommitReviewing {
    private let result: Result<AIPreCommitReviewResult, Error>
    private var calls: [AIPreCommitReviewCall] = []

    init(result: Result<AIPreCommitReviewResult, Error>) {
        self.result = result
    }

    func recordedCalls() -> [AIPreCommitReviewCall] {
        calls
    }

    func review(
        wc: URL,
        paths: [String],
        privacySettings: AIPrivacySettings
    ) async throws -> AIPreCommitReviewResult {
        calls.append(AIPreCommitReviewCall(
            wc: wc,
            paths: paths,
            privacySettings: privacySettings
        ))
        return try result.get()
    }
}

private struct AICommitMessageCall: Equatable, Sendable {
    let wc: URL
    let paths: [String]
    let format: AICommitMessageFormat
    let privacySettings: AIPrivacySettings
}

private actor FakeAICommitMessageGenerator: AICommitMessageGenerating {
    private let result: Result<AICommitMessageDraft, Error>
    private var calls: [AICommitMessageCall] = []

    init(result: Result<AICommitMessageDraft, Error>) {
        self.result = result
    }

    func recordedCalls() -> [AICommitMessageCall] {
        calls
    }

    func generateCommitMessage(
        wc: URL,
        paths: [String],
        format: AICommitMessageFormat,
        privacySettings: AIPrivacySettings
    ) async throws -> AICommitMessageDraft {
        calls.append(AICommitMessageCall(
            wc: wc,
            paths: paths,
            format: format,
            privacySettings: privacySettings
        ))
        return try result.get()
    }
}
