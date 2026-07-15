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
    private let projectPropertyLoader: ProjectPropertyLoading?
    private var selectItemsAutomatically: Bool
    private var useTrashWhenReverting: Bool
    private let revertSafetyService: RevertSafetyService
    private var projectPropertyLoadGeneration = 0

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
    public private(set) var projectProperties: ProjectPropertyPolicy
    public private(set) var projectPropertyLoadError: String?
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
        commitMessageHistoryProvider: (any CommitMessageHistoryProviding)? = nil,
        projectPropertyLoader: ProjectPropertyLoading? = nil,
        projectProperties: ProjectPropertyPolicy = ProjectPropertyPolicy(properties: []),
        selectItemsAutomatically: Bool = true,
        useTrashWhenReverting: Bool = false,
        revertSafetyService: RevertSafetyService = RevertSafetyService()
    ) {
        self.workingCopy = workingCopy
        self.commitProvider = commitProvider
        self.statusProvider = statusProvider
        self.aiCommitMessageGenerator = aiCommitMessageGenerator
        self.aiPreCommitReviewer = aiPreCommitReviewer
        self.commitMessageHistoryProvider = commitMessageHistoryProvider
        self.projectPropertyLoader = projectPropertyLoader
        self.selectItemsAutomatically = selectItemsAutomatically
        self.useTrashWhenReverting = useTrashWhenReverting
        self.revertSafetyService = revertSafetyService
        self.projectProperties = projectProperties
        self.candidateStatuses = CommitSelectionPolicy.candidates(from: statuses)
        self.selectedPaths = selectItemsAutomatically
            ? CommitSelectionPolicy.defaultSelectedPaths(from: statuses)
            : []
        self.message = projectProperties.commit.initialMessage ?? ""
    }

    public var orderedSelectedPaths: [String] {
        candidateStatuses.map(\.path).filter { selectedPaths.contains($0) }
    }

    public var availableChangelists: [String] {
        Array(Set(candidateStatuses.compactMap(\.changelist))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    public func updateSettings(
        selectItemsAutomatically: Bool,
        useTrashWhenReverting: Bool
    ) {
        self.selectItemsAutomatically = selectItemsAutomatically
        self.useTrashWhenReverting = useTrashWhenReverting
    }

    public func selectChangelist(_ name: String?) {
        selectedChangelist = name
        guard let name else {
            selectedPaths = selectItemsAutomatically
                ? CommitSelectionPolicy.defaultSelectedPaths(from: candidateStatuses)
                : []
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
            && projectPropertyLoadError == nil
            && CommitMessagePolicy.validationError(for: message, properties: projectProperties) == nil
            && state != .committing
            && state != .reverting
    }

    public var overlongMessageLineNumbers: [Int] {
        CommitMessagePolicy.overlongLineNumbers(in: message, properties: projectProperties)
    }

    public var issueReferences: [BugtraqIssueReference] {
        projectProperties.bugtraq.issueReferences(in: message)
    }

    @discardableResult
    public func applyBugtraqIssueInput(_ input: String) -> Bool {
        guard let updated = projectProperties.bugtraq.applyingIssueInput(input, to: message) else { return false }
        message = updated
        return true
    }

    public func setSelected(_ isSelected: Bool, for path: String) {
        selectedChangelist = nil
        if isSelected {
            selectedPaths.insert(path)
        } else {
            selectedPaths.remove(path)
        }
    }

    /// 选择变化后刷新提示；实际提交仍会重新读取，避免异步 UI 刷新造成门控绕过。
    public func refreshProjectProperties(for paths: [String]? = nil) async {
        let generation = beginProjectPropertyLoad()
        do {
            let properties = try await loadProjectProperties(for: paths ?? orderedSelectedPaths)
            guard generation == projectPropertyLoadGeneration else { return }
            projectProperties = properties
            projectPropertyLoadError = nil
            if message.isEmpty, let template = projectProperties.commit.initialMessage {
                message = template
            }
        } catch {
            guard generation == projectPropertyLoadGeneration else { return }
            projectPropertyLoadError = "projectPropertiesLoadFailed"
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
        let properties: ProjectPropertyPolicy
        let generation = beginProjectPropertyLoad()
        do {
            properties = try await loadProjectProperties(for: paths)
            if generation == projectPropertyLoadGeneration {
                projectProperties = properties
                projectPropertyLoadError = nil
            }
        } catch {
            projectPropertyLoadError = "projectPropertiesLoadFailed"
            state = .error("projectPropertiesLoadFailed")
            return
        }

        if let validationError = CommitMessagePolicy.validationError(for: message, properties: properties) {
            state = .error("logMessageTooShort:\(validationError.required)")
            return
        }

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
        var backup = RevertTrashBackup()
        do {
            if useTrashWhenReverting {
                let statuses = try await statusProvider.status(wc: workingCopy)
                backup = try revertSafetyService.stage(
                    workingCopy: workingCopy,
                    selectedPaths: targets,
                    statuses: statuses,
                    recursive: recursive
                )
            }
            try await commitProvider.revert(wc: workingCopy, paths: targets, recursive: recursive)
        } catch {
            let reportedError = revertSafetyService.errorAfterRestoring(
                backup,
                operationError: error
            )
            state = .error(String(describing: reportedError))
            return
        }
        do {
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

    private func loadProjectProperties(for paths: [String]) async throws -> ProjectPropertyPolicy {
        guard let projectPropertyLoader else { return projectProperties }
        return try await projectPropertyLoader(paths)
    }

    private func beginProjectPropertyLoad() -> Int {
        projectPropertyLoadGeneration += 1
        return projectPropertyLoadGeneration
    }
}

extension SvnService: CommitProviding {}
