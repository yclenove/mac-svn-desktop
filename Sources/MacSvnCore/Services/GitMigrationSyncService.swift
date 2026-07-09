import Foundation

public actor GitMigrationSyncService {
    private let store: any GitMigrationSyncRecordStoring
    private let gitBackend: any GitBackend

    public init(store: any GitMigrationSyncRecordStoring, gitBackend: any GitBackend) {
        self.store = store
        self.gitBackend = gitBackend
    }

    public func loadRecords() async throws -> [GitMigrationSyncRecord] {
        try await store.loadRecords()
    }

    @discardableResult
    public func registerMigration(
        sourceURL: String,
        repository: URL,
        targetRemote: String?
    ) async throws -> GitMigrationSyncRecord {
        try await store.addRecord(
            sourceURL: sourceURL,
            repository: repository,
            targetRemote: targetRemote
        )
    }

    public func sync(
        record: GitMigrationSyncRecord,
        syncedAt: Date = Date()
    ) async throws -> GitMigrationSyncReport {
        let repository = URL(fileURLWithPath: record.repositoryPath)
        var completedSteps: [GitMigrationSyncStep] = []

        try await gitBackend.svnFetch(repository: repository)
        completedSteps.append(.gitSvnFetch)

        let migratedRevisions = try await gitBackend.gitSvnRevisions(repository: repository)
        completedSteps.append(.revisionScan)
        let latestRevision = migratedRevisions.map(\.revision).max { $0.value < $1.value }

        if let remote = normalizedRemote(record.targetRemote) {
            try await gitBackend.pushAll(repository: repository, remote: remote)
            completedSteps.append(.gitPushBranches)
            try await gitBackend.pushTags(repository: repository, remote: remote)
            completedSteps.append(.gitPushTags)
        }

        let updatedRecord = try await store.updateSyncMetadata(
            id: record.id,
            latestRevision: latestRevision,
            syncedAt: syncedAt
        )

        return GitMigrationSyncReport(
            recordID: record.id,
            repositoryPath: record.repositoryPath,
            completedSteps: completedSteps,
            latestRevision: latestRevision,
            updatedRecord: updatedRecord
        )
    }

    @discardableResult
    public func updateSchedule(
        id: UUID,
        isEnabled: Bool,
        intervalMinutes: Int?
    ) async throws -> GitMigrationSyncRecord {
        try await store.updateSchedule(
            id: id,
            isEnabled: isEnabled,
            intervalMinutes: intervalMinutes
        )
    }

    private func normalizedRemote(_ remote: String?) -> String? {
        let trimmedRemote = remote?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedRemote, !trimmedRemote.isEmpty else {
            return nil
        }

        return trimmedRemote
    }
}
