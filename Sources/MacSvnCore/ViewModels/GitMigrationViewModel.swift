import Foundation
import Observation

public protocol GitMigrationProviding: Sendable {
    func snapshotMigrate(
        sourceURL: String,
        destination: URL,
        revision: Revision?,
        commitMessage: String,
        auth: Credential?
    ) async throws -> GitMigrationReport
    func historyMigrate(
        sourceURL: String,
        destination: URL,
        layout: GitMigrationRepositoryLayout,
        authorMappings: [GitMigrationAuthorMapping],
        revisionRange: RevisionRange?,
        auth: Credential?
    ) async throws -> GitMigrationReport
}

public enum GitMigrationState: Equatable, Sendable {
    case idle
    case running
    case completed(GitMigrationReport)
    case error(String)
}

@MainActor
@Observable
public final class GitMigrationViewModel {
    private let provider: any GitMigrationProviding

    public private(set) var state: GitMigrationState = .idle
    public private(set) var report: GitMigrationReport?

    public init(provider: any GitMigrationProviding) {
        self.provider = provider
    }

    public func snapshotMigrate(
        sourceURL: String,
        destination: URL,
        revision: Revision? = nil,
        commitMessage: String,
        auth: Credential? = nil
    ) async {
        let trimmedSourceURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSourceURL.isEmpty else {
            report = nil
            state = .error(String(describing: GitMigrationError.emptySourceURL))
            return
        }

        guard !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            report = nil
            state = .error(String(describing: GitMigrationError.emptyCommitMessage))
            return
        }

        state = .running
        report = nil

        do {
            let completedReport = try await provider.snapshotMigrate(
                sourceURL: trimmedSourceURL,
                destination: destination,
                revision: revision,
                commitMessage: commitMessage,
                auth: auth
            )
            report = completedReport
            state = .completed(completedReport)
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func historyMigrate(
        sourceURL: String,
        destination: URL,
        layout: GitMigrationRepositoryLayout,
        authorMappings: [GitMigrationAuthorMapping],
        revisionRange: RevisionRange? = nil,
        auth: Credential? = nil
    ) async {
        let trimmedSourceURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSourceURL.isEmpty else {
            report = nil
            state = .error(String(describing: GitMigrationError.emptySourceURL))
            return
        }

        state = .running
        report = nil

        do {
            let completedReport = try await provider.historyMigrate(
                sourceURL: trimmedSourceURL,
                destination: destination,
                layout: layout,
                authorMappings: authorMappings,
                revisionRange: revisionRange,
                auth: auth
            )
            report = completedReport
            state = .completed(completedReport)
        } catch {
            state = .error(String(describing: error))
        }
    }
}

extension GitMigrationService: GitMigrationProviding {}
