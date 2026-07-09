import Foundation

public protocol GitMigrationSvnExporting: Sendable {
    func export(url: String, to destination: URL, revision: Revision?, auth: Credential?) async throws
}

public actor GitMigrationService {
    private let svnExporter: any GitMigrationSvnExporting
    private let gitBackend: any GitBackend
    private let authorMapper: GitMigrationAuthorMapper
    private let revisionReconciler: GitMigrationRevisionReconciler
    private let fileManager: FileManager

    public init(
        svnExporter: any GitMigrationSvnExporting,
        gitBackend: any GitBackend,
        authorMapper: GitMigrationAuthorMapper = GitMigrationAuthorMapper(),
        revisionReconciler: GitMigrationRevisionReconciler = GitMigrationRevisionReconciler(),
        fileManager: FileManager = .default
    ) {
        self.svnExporter = svnExporter
        self.gitBackend = gitBackend
        self.authorMapper = authorMapper
        self.revisionReconciler = revisionReconciler
        self.fileManager = fileManager
    }

    public func snapshotMigrate(
        sourceURL: String,
        destination: URL,
        revision: Revision? = nil,
        commitMessage: String,
        auth: Credential? = nil
    ) async throws -> GitMigrationReport {
        let trimmedSourceURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSourceURL.isEmpty else {
            throw GitMigrationError.emptySourceURL
        }

        guard !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitMigrationError.emptyCommitMessage
        }

        try validateDestinationIsEmpty(destination)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try await svnExporter.export(url: trimmedSourceURL, to: destination, revision: revision, auth: auth)
        try await gitBackend.initRepository(at: destination)
        try await gitBackend.addAll(repository: destination)
        try await gitBackend.commit(repository: destination, message: commitMessage)

        return GitMigrationReport(
            mode: .snapshot,
            sourceURL: trimmedSourceURL,
            destinationPath: destination.path,
            revision: revision,
            commitMessage: commitMessage,
            completedSteps: [.svnExport, .gitInit, .gitAdd, .gitCommit]
        )
    }

    public func historyMigrate(
        sourceURL: String,
        destination: URL,
        layout: GitMigrationRepositoryLayout,
        authorMappings: [GitMigrationAuthorMapping],
        revisionRange: RevisionRange? = nil,
        auth: Credential? = nil
    ) async throws -> GitMigrationReport {
        let trimmedSourceURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSourceURL.isEmpty else {
            throw GitMigrationError.emptySourceURL
        }

        let authorsFile = destination
            .deletingLastPathComponent()
            .appendingPathComponent("\(destination.lastPathComponent)-authors.txt")

        try authorMapper.validateComplete(authorMappings)
        try validateDestinationIsEmpty(destination)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try authorMapper.exportAuthorsFile(authorMappings, to: authorsFile)
        try await gitBackend.svnClone(
            sourceURL: trimmedSourceURL,
            destination: destination,
            authorsFile: authorsFile,
            layout: layout,
            revisionRange: revisionRange,
            username: auth?.username
        )

        return GitMigrationReport(
            mode: .historyPreserving,
            sourceURL: trimmedSourceURL,
            destinationPath: destination.path,
            revision: nil,
            commitMessage: "",
            completedSteps: [.authorsFile, .gitSvnClone],
            authorsFilePath: authorsFile.path,
            layout: layout,
            revisionRange: revisionRange
        )
    }

    public func reconcileHistoryMigration(
        sourceRevisions: [Revision],
        gitRepository: URL
    ) async throws -> GitMigrationRevisionReconciliationReport {
        let migratedRevisions = try await gitBackend.gitSvnRevisions(repository: gitRepository)
        return revisionReconciler.reconcile(
            sourceRevisions: sourceRevisions,
            migratedRevisions: migratedRevisions
        )
    }

    private func validateDestinationIsEmpty(_ destination: URL) throws {
        guard fileManager.fileExists(atPath: destination.path) else {
            return
        }

        let contents = try fileManager.contentsOfDirectory(
            at: destination,
            includingPropertiesForKeys: nil
        )

        guard contents.isEmpty else {
            throw GitMigrationError.destinationNotEmpty(path: destination.path)
        }
    }
}

extension SvnService: GitMigrationSvnExporting {}
