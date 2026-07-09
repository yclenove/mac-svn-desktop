import Foundation

public struct GitMigrationRevisionReconciler: Sendable {
    public init() {}

    public func reconcile(
        sourceRevisions: [Revision],
        migratedRevisions: [GitSvnRevisionMetadata]
    ) -> GitMigrationRevisionReconciliationReport {
        let source = Set(sourceRevisions)
        let migrated = Set(migratedRevisions.map(\.revision))

        return GitMigrationRevisionReconciliationReport(
            sourceRevisionCount: source.count,
            migratedRevisionCount: migrated.count,
            missingRevisions: source.subtracting(migrated).sorted { $0.value < $1.value },
            unexpectedRevisions: migrated.subtracting(source).sorted { $0.value < $1.value }
        )
    }
}
