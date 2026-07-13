import Foundation
import Observation

public protocol CommitProviding: Sendable {
    func commit(
        wc: URL,
        paths: [String],
        message: String,
        auth: Credential?,
        skipGuardWarnings: Bool,
        keepLocks: Bool
    ) async throws -> Revision

    func revert(wc: URL, paths: [String], recursive: Bool) async throws
}

public enum CommitViewState: Equatable, Sendable {
    case idle
    case committing
    case committed(Revision)
    case reverting
    case reverted
    case guardWarnings([CommitGuardIssue])
    case error(String)
}

public enum AICommitMessageViewState: Equatable, Sendable {
    case idle
    case generating
    case generated(AICommitMessageDraft)
    case error(String)
}

public enum AIPreCommitReviewViewState: Equatable, Sendable {
    case idle
    case reviewing
    case reviewed(AIPreCommitReviewResult)
    case error(String)
}

public enum CommitMessageHistoryViewState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

public enum CommitSelectionPolicy {
    /// 提交对话框候选：版本化变更 + 冲突 + 未版本（勾选未版本将在提交前 add）
    public static func candidates(from statuses: [FileStatus]) -> [FileStatus] {
        statuses.filter { status in
            switch status.itemStatus {
            case .modified, .added, .deleted, .replaced, .conflicted, .unversioned:
                return true
            default:
                return status.isTreeConflict
            }
        }
    }

    /// 默认勾选修改项；未版本与冲突不自动勾选（对齐小乌龟）
    public static func defaultSelectedPaths(from statuses: [FileStatus]) -> Set<String> {
        Set(candidates(from: statuses).compactMap { status in
            guard status.itemStatus != .conflicted,
                  status.itemStatus != .unversioned,
                  !status.isTreeConflict,
                  !ChangelistPolicy.isIgnoredOnCommit(status.changelist) else {
                return nil
            }

            return status.path
        })
    }
}

@MainActor
@Observable
public final class CommitViewModel {
    private let workingCopy: URL
    private let commitProvider: any CommitProviding
    private let statusProvider: any StatusProviding
    private let aiCommitMessageGenerator: (any AICommitMessageGenerating)?
    private let aiPreCommitReviewer: (any AIPreCommitReviewing)?
    private let commitMessageHistoryProvider: (any CommitMessageHistoryProviding)?

    public private(set) var state: CommitViewState = .idle
    public private(set) var aiCommitMessageState: AICommitMessageViewState = .idle
    public private(set) var aiPreCommitReviewState: AIPreCommitReviewViewState = .idle
    public private(set) var messageHistoryState: CommitMessageHistoryViewState = .idle
    public private(set) var committedRevision: Revision?
    public private(set) var aiCommitMessageDraft: AICommitMessageDraft?
    public private(set) var aiPreCommitReviewResult: AIPreCommitReviewResult?
    public private(set) var recentMessages: [String] = []
    public private(set) var refreshedStatuses: [FileStatus] = []
    public private(set) var guardIssues: [CommitGuardIssue] = []
    public let candidateStatuses: [FileStatus]
    public var selectedPaths: Set<String>
    public private(set) var selectedChangelist: String?
    public var message = ""
    /// Keep locks：提交后保留锁（`svn commit --no-unlock`）
    public var keepLocks = false

    public init(
        workingCopy: URL,
        statuses: [FileStatus],
        commitProvider: any CommitProviding,
        statusProvider: any StatusProviding,
        aiCommitMessageGenerator: (any AICommitMessageGenerating)? = nil,
        aiPreCommitReviewer: (any AIPreCommitReviewing)? = nil,
        commitMessageHistoryProvider: (any CommitMessageHistoryProviding)? = nil
    ) {
        self.workingCopy = workingCopy
        self.commitProvider = commitProvider
        self.statusProvider = statusProvider
        self.aiCommitMessageGenerator = aiCommitMessageGenerator
        self.aiPreCommitReviewer = aiPreCommitReviewer
        self.commitMessageHistoryProvider = commitMessageHistoryProvider
        self.candidateStatuses = CommitSelectionPolicy.candidates(from: statuses)
        self.selectedPaths = CommitSelectionPolicy.defaultSelectedPaths(from: statuses)
    }

    public var orderedSelectedPaths: [String] {
        candidateStatuses.map(\.path).filter { selectedPaths.contains($0) }
    }

    public var availableChangelists: [String] {
        Array(Set(candidateStatuses.compactMap(\.changelist))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    public func selectChangelist(_ name: String?) {
        selectedChangelist = name
        guard let name else {
            selectedPaths = CommitSelectionPolicy.defaultSelectedPaths(from: candidateStatuses)
            return
        }
        selectedPaths = Set(candidateStatuses.compactMap { status in
            guard status.changelist == name,
                  status.itemStatus != .conflicted,
                  status.itemStatus != .unversioned,
                  !status.isTreeConflict else { return nil }
            return status.path
        })
    }

    public var canCommit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !orderedSelectedPaths.isEmpty
            && state != .committing
            && state != .reverting
    }

    public func setSelected(_ isSelected: Bool, for path: String) {
        selectedChangelist = nil
        if isSelected {
            selectedPaths.insert(path)
        } else {
            selectedPaths.remove(path)
        }
    }

    public func loadRecentMessages() async {
        guard let commitMessageHistoryProvider else {
            recentMessages = []
            messageHistoryState = .loaded
            return
        }

        messageHistoryState = .loading

        do {
            recentMessages = try await commitMessageHistoryProvider.recentMessages(workingCopy: workingCopy)
            messageHistoryState = .loaded
        } catch {
            recentMessages = []
            messageHistoryState = .error(String(describing: error))
        }
    }

    public func reuseRecentMessage(_ recentMessage: String) {
        message = recentMessage
    }

    public func generateAICommitMessage(
        format: AICommitMessageFormat = .conventionalChinese,
        privacySettings: AIPrivacySettings = AIPrivacySettings()
    ) async {
        guard let aiCommitMessageGenerator else {
            aiCommitMessageDraft = nil
            aiCommitMessageState = .error("aiCommitMessageGeneratorUnavailable")
            return
        }

        aiCommitMessageState = .generating

        do {
            let draft = try await aiCommitMessageGenerator.generateCommitMessage(
                wc: workingCopy,
                paths: orderedSelectedPaths,
                format: format,
                privacySettings: privacySettings
            )
            message = draft.message
            aiCommitMessageDraft = draft
            aiCommitMessageState = .generated(draft)
        } catch {
            aiCommitMessageDraft = nil
            aiCommitMessageState = .error(String(describing: error))
        }
    }

    public func runAIPreCommitReview(
        privacySettings: AIPrivacySettings = AIPrivacySettings()
    ) async {
        guard let aiPreCommitReviewer else {
            aiPreCommitReviewResult = nil
            aiPreCommitReviewState = .error("aiPreCommitReviewerUnavailable")
            return
        }

        aiPreCommitReviewState = .reviewing

        do {
            let result = try await aiPreCommitReviewer.review(
                wc: workingCopy,
                paths: orderedSelectedPaths,
                privacySettings: privacySettings
            )
            aiPreCommitReviewResult = result
            aiPreCommitReviewState = .reviewed(result)
        } catch {
            aiPreCommitReviewResult = nil
            aiPreCommitReviewState = .error(String(describing: error))
        }
    }

    public func commit(auth: Credential?, skipGuardWarnings: Bool = false) async {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            state = .error("emptyCommitMessage")
            return
        }

        let paths = orderedSelectedPaths
        guard !paths.isEmpty else {
            state = .error("noSelectedPaths")
            return
        }

        state = .committing

        do {
            let revision = try await commitProvider.commit(
                wc: workingCopy,
                paths: paths,
                message: message,
                auth: auth,
                skipGuardWarnings: skipGuardWarnings,
                keepLocks: keepLocks
            )
            committedRevision = revision
            guardIssues = []
            refreshedStatuses = try await statusProvider.status(wc: workingCopy)
            state = .committed(revision)
            await recordSuccessfulMessage(message)
        } catch SvnServiceError.commitGuardWarnings(let issues) {
            guardIssues = issues
            state = .guardWarnings(issues)
        } catch {
            state = .error(String(describing: error))
        }
    }

    /// 单项/多选还原：先业务成功再刷新候选 status。
    public func revertSelected(paths: [String]? = nil, recursive: Bool = false) async {
        let targets = paths ?? orderedSelectedPaths
        guard !targets.isEmpty else {
            state = .error("noSelectedPaths")
            return
        }

        state = .reverting

        do {
            try await commitProvider.revert(wc: workingCopy, paths: targets, recursive: recursive)
            refreshedStatuses = try await statusProvider.status(wc: workingCopy)
            for path in targets {
                selectedPaths.remove(path)
            }
            state = .reverted
        } catch {
            state = .error(String(describing: error))
        }
    }

    private func recordSuccessfulMessage(_ message: String) async {
        guard let commitMessageHistoryProvider else {
            return
        }

        do {
            try await commitMessageHistoryProvider.record(message: message, workingCopy: workingCopy)
            recentMessages = try await commitMessageHistoryProvider.recentMessages(workingCopy: workingCopy)
            messageHistoryState = .loaded
        } catch {
            messageHistoryState = .error(String(describing: error))
        }
    }
}

extension SvnService: CommitProviding {}
