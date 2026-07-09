import XCTest
@testable import MacSvnCore

final class GitSvnMetadataParserTests: XCTestCase {
    func testParsesGitSvnIdsFromCommitBodiesDeduplicatedAndSorted() {
        let text = """
        initial import

        git-svn-id: file:///repo/trunk@3 abc

        branch work
        git-svn-id: file:///repo/branches/feature@5 abc

        duplicate
        git-svn-id: file:///repo/trunk@3 abc
        """

        XCTAssertEqual(GitSvnMetadataParser.parseRevisions(from: text), [
            GitSvnRevisionMetadata(revision: Revision(3)),
            GitSvnRevisionMetadata(revision: Revision(5))
        ])
    }

    func testIgnoresCommitBodiesWithoutGitSvnIds() {
        XCTAssertEqual(GitSvnMetadataParser.parseRevisions(from: "plain git commit"), [])
    }
}
