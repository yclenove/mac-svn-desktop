import Foundation
import Observation

public protocol CommitProviding: Sendable {
    func commit(
        wc: URL,
        paths: [String],
        message: String,
        auth: Credential?,
        skipGuardWarnings: Bool
    ) async throws -> Revision
}

public enum CommitViewState: Equatable, Sendable {
    case idle
    case committing
    case committed(Revision)
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

public enum CommitSelectionPolicy {
    public static func candidates(from statuses: [FileStatus]) -> [FileStatus] {
        statuses.filter { status in
            switch status.itemStatus {
            case .modified, .added, .deleted, .replaced, .conflicted:
                return true
            default:
                return status.isTreeConflict
            }
        }
    }

    public static func defaultSelectedPaths(from statuses: [FileStatus]) -> Set<String> {
        Set(candidates(from: statuses).compactMap { status in
            guard status.itemStatus != .conflicted, !status.isTreeConflict else {
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

    public private(set) var state: CommitViewState = .idle
    public private(set) var aiCommitMessageState: AICommitMessageViewState = .idle
    public private(set) var aiPreCommitReviewState: AIPreCommitReviewViewState = .idle
    public private(set) var committedRevision: Revision?
    public private(set) var aiCommitMessageDraft: AICommitMessageDraft?
    public private(set) var aiPreCommitReviewResult: AIPreCommitReviewResult?
    public private(set) var refreshedStatuses: [FileStatus] = []
    public private(set) var guardIssues: [CommitGuardIssue] = []
    public let candidateStatuses: [FileStatus]
    public var selectedPaths: Set<String>
    public var message = ""

    public init(
        workingCopy: URL,
        statuses: [FileStatus],
        commitProvider: any CommitProviding,
        statusProvider: any StatusProviding,
        aiCommitMessageGenerator: (any AICommitMessageGenerating)? = nil,
        aiPreCommitReviewer: (any AIPreCommitReviewing)? = nil
    ) {
        self.workingCopy = workingCopy
        self.commitProvider = commitProvider
        self.statusProvider = statusProvider
        self.aiCommitMessageGenerator = aiCommitMessageGenerator
        self.aiPreCommitReviewer = aiPreCommitReviewer
        self.candidateStatuses = CommitSelectionPolicy.candidates(from: statuses)
        self.selectedPaths = CommitSelectionPolicy.defaultSelectedPaths(from: statuses)
    }

    public var orderedSelectedPaths: [String] {
        candidateStatuses.map(\.path).filter { selectedPaths.contains($0) }
    }

    public var canCommit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !orderedSelectedPaths.isEmpty
            && state != .committing
    }

    public func setSelected(_ isSelected: Bool, for path: String) {
        if isSelected {
            selectedPaths.insert(path)
        } else {
            selectedPaths.remove(path)
        }
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
                skipGuardWarnings: skipGuardWarnings
            )
            committedRevision = revision
            guardIssues = []
            refreshedStatuses = try await statusProvider.status(wc: workingCopy)
            state = .committed(revision)
        } catch SvnServiceError.commitGuardWarnings(let issues) {
            guardIssues = issues
            state = .guardWarnings(issues)
        } catch {
            state = .error(String(describing: error))
        }
    }
}

extension SvnService: CommitProviding {}
