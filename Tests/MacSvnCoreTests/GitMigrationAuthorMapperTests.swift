import Foundation
import XCTest
@testable import MacSvnCore

final class GitMigrationAuthorMapperTests: XCTestCase {
    func testDraftMappingsAreSortedAndEmptyUntilUserFillsGitIdentity() {
        let mapper = GitMigrationAuthorMapper()
        let mappings = mapper.draftMappings(from: [
            GitMigrationAuthor(svnUsername: "zhangsan"),
            GitMigrationAuthor(svnUsername: "lisi"),
            GitMigrationAuthor(svnUsername: "zhangsan")
        ])

        XCTAssertEqual(mappings, [
            GitMigrationAuthorMapping(svnUsername: "lisi", gitName: "", gitEmail: ""),
            GitMigrationAuthorMapping(svnUsername: "zhangsan", gitName: "", gitEmail: "")
        ])
        XCTAssertEqual(mapper.coverage(for: mappings), GitMigrationAuthorMappingCoverage(totalCount: 2, coveredCount: 0))
        XCTAssertFalse(mapper.coverage(for: mappings).isComplete)
    }

    func testCoverageRequiresNonEmptyNameAndEmailForEveryAuthor() {
        let mapper = GitMigrationAuthorMapper()
        let mappings = [
            GitMigrationAuthorMapping(svnUsername: "lisi", gitName: "李四", gitEmail: "lisi@example.com"),
            GitMigrationAuthorMapping(svnUsername: "zhangsan", gitName: " ", gitEmail: "zhangsan@example.com")
        ]

        XCTAssertEqual(mapper.coverage(for: mappings), GitMigrationAuthorMappingCoverage(totalCount: 2, coveredCount: 1))
        XCTAssertThrowsError(try mapper.validateComplete(mappings)) { error in
            XCTAssertEqual(error as? GitMigrationAuthorMappingError, .incompleteAuthors(["zhangsan"]))
        }
    }

    func testAuthorsFileRoundTripsGitSvnFormat() throws {
        let mapper = GitMigrationAuthorMapper()
        let mappings = [
            GitMigrationAuthorMapping(svnUsername: "lisi", gitName: "李四", gitEmail: "lisi@example.com"),
            GitMigrationAuthorMapping(svnUsername: "zhangsan", gitName: "张三", gitEmail: "zhangsan@example.com")
        ]

        let text = try mapper.authorsFileContents(from: mappings)

        XCTAssertEqual(text, "lisi = 李四 <lisi@example.com>\nzhangsan = 张三 <zhangsan@example.com>\n")
        XCTAssertEqual(try mapper.parseAuthorsFile(text), mappings)
    }

    func testInvalidAuthorsFileLineThrowsError() {
        let mapper = GitMigrationAuthorMapper()

        XCTAssertThrowsError(try mapper.parseAuthorsFile("not valid\n")) { error in
            XCTAssertEqual(error as? GitMigrationAuthorMappingError, .invalidAuthorsFileLine("not valid"))
        }
    }

    func testImportAndExportAuthorsFile() throws {
        let mapper = GitMigrationAuthorMapper()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitMigrationAuthorMapperTests-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("authors.txt")
        let mappings = [
            GitMigrationAuthorMapping(svnUsername: "lisi", gitName: "李四", gitEmail: "lisi@example.com")
        ]
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try mapper.exportAuthorsFile(mappings, to: file)

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "lisi = 李四 <lisi@example.com>\n")
        XCTAssertEqual(try mapper.importAuthorsFile(from: file), mappings)
    }
}
