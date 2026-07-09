import Foundation
import Observation

public protocol GitMigrationSyncProviding: Sendable {
    func loadRecords() async throws -> [GitMigrationSyncRecord]
    func registerMigration(
        sourceURL: String,
        repository: URL,
        targetRemote: String?
    ) async throws -> GitMigrationSyncRecord
    func sync(record: GitMigrationSyncRecord) async throws -> GitMigrationSyncReport
}

public enum GitMigrationSyncState: Equatable, Sendable {
    case idle
    case loading
    case running
    case completed(GitMigrationSyncReport)
    case error(String)
}

@MainActor
@Observable
public final class GitMigrationSyncViewModel {
    private let provider: any GitMigrationSyncProviding

    public private(set) var state: GitMigrationSyncState = .idle
    public private(set) var records: [GitMigrationSyncRecord] = []
    public private(set) var lastReport: GitMigrationSyncReport?

    public init(provider: any GitMigrationSyncProviding) {
        self.provider = provider
    }

    public func loadRecords() async {
        state = .loading

        do {
            records = try await provider.loadRecords()
            state = .idle
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func registerMigration(
        sourceURL: String,
        repository: URL,
        targetRemote: String? = nil
    ) async {
        state = .running

        do {
            let record = try await provider.registerMigration(
                sourceURL: sourceURL,
                repository: repository,
                targetRemote: targetRemote
            )
            upsert(record)
            state = .idle
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func sync(_ record: GitMigrationSyncRecord) async {
        state = .running
        lastReport = nil

        do {
            let report = try await provider.sync(record: record)
            lastReport = report
            upsert(report.updatedRecord)
            state = .completed(report)
        } catch {
            state = .error(String(describing: error))
        }
    }

    private func upsert(_ record: GitMigrationSyncRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
    }
}

extension GitMigrationSyncService: GitMigrationSyncProviding {
    public func sync(record: GitMigrationSyncRecord) async throws -> GitMigrationSyncReport {
        try await sync(record: record, syncedAt: Date())
    }
}
