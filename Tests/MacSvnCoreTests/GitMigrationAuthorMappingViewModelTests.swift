import Foundation
import XCTest
@testable import MacSvnCore

final class GitMigrationAuthorMappingViewModelTests: XCTestCase {
    @MainActor
    func testLoadAuthorsCreatesDraftRowsAndCoverage() {
        let viewModel = GitMigrationAuthorMappingViewModel(mapper: GitMigrationAuthorMapper())

        viewModel.loadAuthors([
            GitMigrationAuthor(svnUsername: "zhangsan"),
            GitMigrationAuthor(svnUsername: "lisi")
        ])

        XCTAssertEqual(viewModel.state, .editing)
        XCTAssertEqual(viewModel.mappings.map(\.svnUsername), ["lisi", "zhangsan"])
        XCTAssertEqual(viewModel.coverage, GitMigrationAuthorMappingCoverage(totalCount: 2, coveredCount: 0))
        XCTAssertFalse(viewModel.canStartMigration)
    }

    @MainActor
    func testUpdateMappingRefreshesCoverageAndCanStartMigration() {
        let viewModel = GitMigrationAuthorMappingViewModel(mapper: GitMigrationAuthorMapper())
        viewModel.loadAuthors([GitMigrationAuthor(svnUsername: "lisi")])

        viewModel.updateMapping(svnUsername: "lisi", gitName: "李四", gitEmail: "lisi@example.com")

        XCTAssertEqual(viewModel.mappings, [
            GitMigrationAuthorMapping(svnUsername: "lisi", gitName: "李四", gitEmail: "lisi@example.com")
        ])
        XCTAssertEqual(viewModel.coverage, GitMigrationAuthorMappingCoverage(totalCount: 1, coveredCount: 1))
        XCTAssertTrue(viewModel.canStartMigration)
    }

    @MainActor
    func testExportIncompleteMappingStoresError() async {
        let viewModel = GitMigrationAuthorMappingViewModel(mapper: GitMigrationAuthorMapper())
        viewModel.loadAuthors([GitMigrationAuthor(svnUsername: "lisi")])

        await viewModel.exportAuthorsFile(to: URL(fileURLWithPath: "/tmp/authors.txt"))

        XCTAssertEqual(viewModel.state, .error(String(describing: GitMigrationAuthorMappingError.incompleteAuthors(["lisi"]))))
    }

    @MainActor
    func testExportCompleteMappingWritesFileAndStoresExportedState() async throws {
        let viewModel = GitMigrationAuthorMappingViewModel(mapper: GitMigrationAuthorMapper())
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitMigrationAuthorMappingViewModelTests-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("authors.txt")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        viewModel.loadAuthors([GitMigrationAuthor(svnUsername: "lisi")])
        viewModel.updateMapping(svnUsername: "lisi", gitName: "李四", gitEmail: "lisi@example.com")

        await viewModel.exportAuthorsFile(to: file)

        XCTAssertEqual(viewModel.state, .exported(file))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "lisi = 李四 <lisi@example.com>\n")
    }

    @MainActor
    func testImportAuthorsFileUpdatesMappingsAndCoverage() async throws {
        let viewModel = GitMigrationAuthorMappingViewModel(mapper: GitMigrationAuthorMapper())
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitMigrationAuthorMappingViewModelTests-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("authors.txt")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "lisi = 李四 <lisi@example.com>\n".write(to: file, atomically: true, encoding: .utf8)

        await viewModel.importAuthorsFile(from: file)

        XCTAssertEqual(viewModel.state, .editing)
        XCTAssertEqual(viewModel.mappings, [
            GitMigrationAuthorMapping(svnUsername: "lisi", gitName: "李四", gitEmail: "lisi@example.com")
        ])
        XCTAssertEqual(viewModel.coverage, GitMigrationAuthorMappingCoverage(totalCount: 1, coveredCount: 1))
        XCTAssertTrue(viewModel.canStartMigration)
    }

    @MainActor
    func testImportInvalidAuthorsFileStoresError() async throws {
        let viewModel = GitMigrationAuthorMappingViewModel(mapper: GitMigrationAuthorMapper())
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitMigrationAuthorMappingViewModelTests-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("authors.txt")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "not valid\n".write(to: file, atomically: true, encoding: .utf8)

        await viewModel.importAuthorsFile(from: file)

        XCTAssertEqual(viewModel.state, .error(String(describing: GitMigrationAuthorMappingError.invalidAuthorsFileLine("not valid"))))
        XCTAssertEqual(viewModel.mappings, [])
        XCTAssertEqual(viewModel.coverage, GitMigrationAuthorMappingCoverage(totalCount: 0, coveredCount: 0))
    }

    @MainActor
    func testApplyAISuggestionsMarksPendingReviewUntilEdited() {
        let viewModel = GitMigrationAuthorMappingViewModel(mapper: GitMigrationAuthorMapper())
        viewModel.loadAuthors([
            GitMigrationAuthor(svnUsername: "zhangsan"),
            GitMigrationAuthor(svnUsername: "lisi")
        ])

        viewModel.applyAISuggestions([
            AIAuthorMappingSuggestion(svnUsername: "zhangsan", gitName: "张三", gitEmail: "zhangsan@acme.com")
        ])

        XCTAssertEqual(viewModel.mappings.first(where: { $0.svnUsername == "zhangsan" })?.gitEmail, "zhangsan@acme.com")
        XCTAssertEqual(viewModel.aiPendingReviewUsernames, ["zhangsan"])
        XCTAssertEqual(viewModel.coverage.coveredCount, 1)

        viewModel.updateMapping(svnUsername: "zhangsan", gitName: "张三", gitEmail: "zhangsan@acme.com")
        XCTAssertTrue(viewModel.aiPendingReviewUsernames.isEmpty)
    }

    @MainActor
    func testInferWithAIAppliesSuggestionsViaInferrer() async {
        let viewModel = GitMigrationAuthorMappingViewModel(mapper: GitMigrationAuthorMapper())
        viewModel.loadAuthors([GitMigrationAuthor(svnUsername: "lisi")])
        let inferrer = FakeAuthorMappingInferrer(draft: AIAuthorMappingInferenceDraft(
            suggestions: [
                AIAuthorMappingSuggestion(svnUsername: "lisi", gitName: "李四", gitEmail: "lisi@acme.com")
            ],
            providerID: UUID(),
            promptCount: 1
        ))

        await viewModel.inferWithAI(
            emailDomain: "acme.com",
            privacySettings: AIPrivacySettings(),
            inferrer: inferrer
        )

        XCTAssertEqual(viewModel.state, .editing)
        XCTAssertEqual(viewModel.mappings, [
            GitMigrationAuthorMapping(svnUsername: "lisi", gitName: "李四", gitEmail: "lisi@acme.com")
        ])
        XCTAssertEqual(viewModel.aiPendingReviewUsernames, ["lisi"])
    }
}

private struct FakeAuthorMappingInferrer: AIAuthorMappingInferring {
    let draft: AIAuthorMappingInferenceDraft

    func inferMappings(
        authors: [GitMigrationAuthor],
        emailDomain: String,
        privacySettings: AIPrivacySettings
    ) async throws -> AIAuthorMappingInferenceDraft {
        draft
    }
}
