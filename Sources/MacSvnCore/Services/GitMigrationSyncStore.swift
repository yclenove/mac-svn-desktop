import Foundation

public protocol GitMigrationSyncRecordStoring: Sendable {
    func loadRecords() async throws -> [GitMigrationSyncRecord]
    func addRecord(sourceURL: String, repository: URL, targetRemote: String?) async throws -> GitMigrationSyncRecord
    func updateSyncMetadata(id: UUID, latestRevision: Revision?, syncedAt: Date) async throws -> GitMigrationSyncRecord
}

public actor GitMigrationSyncStore: GitMigrationSyncRecordStoring {
    private let store: PersistenceStore<GitMigrationSyncListFile>
    private var cachedRecords: [GitMigrationSyncRecord] = []

    public init(fileURL: URL) {
        self.store = PersistenceStore(fileURL: fileURL, defaultValue: GitMigrationSyncListFile())
    }

    public func loadRecords() async throws -> [GitMigrationSyncRecord] {
        let file = try store.load()
        cachedRecords = file.records
        return cachedRecords
    }

    public func records() -> [GitMigrationSyncRecord] {
        cachedRecords
    }

    @discardableResult
    public func addRecord(
        sourceURL: String,
        repository: URL,
        targetRemote: String?
    ) async throws -> GitMigrationSyncRecord {
        let trimmedSourceURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSourceURL.isEmpty else {
            throw GitMigrationSyncError.emptySourceURL
        }

        let repositoryPath = repository.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repositoryPath.isEmpty else {
            throw GitMigrationSyncError.emptyRepositoryPath
        }

        var records = try await loadRecords()
        let remote = normalizedRemote(targetRemote)
        let now = Self.currentPersistableDate()

        if let index = records.firstIndex(where: { $0.repositoryPath == repositoryPath }) {
            records[index].sourceURL = trimmedSourceURL
            records[index].targetRemote = remote
            cachedRecords = records
            try store.save(GitMigrationSyncListFile(records: records))
            return records[index]
        }

        let record = GitMigrationSyncRecord(
            id: UUID(),
            sourceURL: trimmedSourceURL,
            repositoryPath: repositoryPath,
            targetRemote: remote,
            createdAt: now,
            lastSyncedAt: nil,
            lastSyncedRevision: nil
        )
        records.append(record)
        cachedRecords = records
        try store.save(GitMigrationSyncListFile(records: records))
        return record
    }

    @discardableResult
    public func updateSyncMetadata(
        id: UUID,
        latestRevision: Revision?,
        syncedAt: Date
    ) async throws -> GitMigrationSyncRecord {
        var records = try await loadRecords()
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw GitMigrationSyncError.recordNotFound(id)
        }

        records[index].lastSyncedRevision = latestRevision
        records[index].lastSyncedAt = syncedAt
        cachedRecords = records
        try store.save(GitMigrationSyncListFile(records: records))
        return records[index]
    }

    private func normalizedRemote(_ remote: String?) -> String? {
        let trimmedRemote = remote?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedRemote, !trimmedRemote.isEmpty else {
            return nil
        }

        return trimmedRemote
    }

    private static func currentPersistableDate() -> Date {
        Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    }
}
