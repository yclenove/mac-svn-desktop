import Foundation
import Observation

public protocol CommitProviding: Sendable {
    func commit(wc: URL, paths: [String], message: String, auth: Credential?) async throws -> Revision
}

public enum CommitViewState: Equatable, Sendable {
    case idle
    case committing
    case committed(Revision)
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

    public private(set) var state: CommitViewState = .idle
    public private(set) var committedRevision: Revision?
    public private(set) var refreshedStatuses: [FileStatus] = []
    public let candidateStatuses: [FileStatus]
    public var selectedPaths: Set<String>
    public var message = ""

    public init(
        workingCopy: URL,
        statuses: [FileStatus],
        commitProvider: any CommitProviding,
        statusProvider: any StatusProviding
    ) {
        self.workingCopy = workingCopy
        self.commitProvider = commitProvider
        self.statusProvider = statusProvider
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

    public func commit(auth: Credential?) async {
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
                auth: auth
            )
            committedRevision = revision
            refreshedStatuses = try await statusProvider.status(wc: workingCopy)
            state = .committed(revision)
        } catch {
            state = .error(String(describing: error))
        }
    }
}

extension SvnService: CommitProviding {}
