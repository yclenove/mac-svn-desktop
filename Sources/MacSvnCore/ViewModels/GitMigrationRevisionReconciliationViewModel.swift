import Foundation
import Observation

public protocol GitMigrationRevisionReconciliationProviding: Sendable {
    func reconcileHistoryMigration(
        sourceRevisions: [Revision],
        gitRepository: URL
    ) async throws -> GitMigrationRevisionReconciliationReport
}

public enum GitMigrationRevisionReconciliationState: Equatable, Sendable {
    case idle
    case running
    case completed(GitMigrationRevisionReconciliationReport)
    case error(String)
}

@MainActor
@Observable
public final class GitMigrationRevisionReconciliationViewModel {
    private let provider: any GitMigrationRevisionReconciliationProviding

    public private(set) var state: GitMigrationRevisionReconciliationState = .idle
    public private(set) var report: GitMigrationRevisionReconciliationReport?

    public init(provider: any GitMigrationRevisionReconciliationProviding) {
        self.provider = provider
    }

    public func reconcile(
        sourceRevisions: [Revision],
        gitRepository: URL
    ) async {
        state = .running
        report = nil

        do {
            let completedReport = try await provider.reconcileHistoryMigration(
                sourceRevisions: sourceRevisions,
                gitRepository: gitRepository
            )
            report = completedReport
            state = .completed(completedReport)
        } catch {
            state = .error(String(describing: error))
        }
    }
}

extension GitMigrationService: GitMigrationRevisionReconciliationProviding {}
