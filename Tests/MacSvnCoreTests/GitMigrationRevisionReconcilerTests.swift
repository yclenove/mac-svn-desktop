import XCTest
@testable import MacSvnCore

final class GitMigrationRevisionReconcilerTests: XCTestCase {
    func testConsistentRevisionsProducePassingReport() {
        let report = GitMigrationRevisionReconciler().reconcile(
            sourceRevisions: [Revision(1), Revision(2), Revision(3)],
            migratedRevisions: [
                GitSvnRevisionMetadata(revision: Revision(3)),
                GitSvnRevisionMetadata(revision: Revision(1)),
                GitSvnRevisionMetadata(revision: Revision(2))
            ]
        )

        XCTAssertEqual(report, GitMigrationRevisionReconciliationReport(
            sourceRevisionCount: 3,
            migratedRevisionCount: 3,
            missingRevisions: [],
            unexpectedRevisions: []
        ))
        XCTAssertTrue(report.isConsistent)
    }

    func testReportsMissingAndUnexpectedRevisions() {
        let report = GitMigrationRevisionReconciler().reconcile(
            sourceRevisions: [Revision(1), Revision(2), Revision(4)],
            migratedRevisions: [
                GitSvnRevisionMetadata(revision: Revision(1)),
                GitSvnRevisionMetadata(revision: Revision(3))
            ]
        )

        XCTAssertEqual(report.missingRevisions, [Revision(2), Revision(4)])
        XCTAssertEqual(report.unexpectedRevisions, [Revision(3)])
        XCTAssertFalse(report.isConsistent)
    }
}
