import Foundation
import Observation

public enum GitMigrationAuthorMappingState: Equatable, Sendable {
    case idle
    case editing
    case inferring
    case exported(URL)
    case error(String)
}

@MainActor
@Observable
public final class GitMigrationAuthorMappingViewModel {
    private let mapper: GitMigrationAuthorMapper

    public private(set) var state: GitMigrationAuthorMappingState = .idle
    public private(set) var mappings: [GitMigrationAuthorMapping] = []
    public private(set) var coverage = GitMigrationAuthorMappingCoverage(totalCount: 0, coveredCount: 0)
    /// AI 推断后待人工复核的用户名集合（FR-GM-03）。
    public private(set) var aiPendingReviewUsernames: Set<String> = []

    public var canStartMigration: Bool {
        coverage.isComplete
    }

    public init(mapper: GitMigrationAuthorMapper) {
        self.mapper = mapper
    }

    public func loadAuthors(_ authors: [GitMigrationAuthor]) {
        mappings = mapper.draftMappings(from: authors)
        aiPendingReviewUsernames = []
        refreshCoverage()
        state = .editing
    }

    public func updateMapping(svnUsername: String, gitName: String, gitEmail: String) {
        guard let index = mappings.firstIndex(where: { $0.svnUsername == svnUsername }) else {
            return
        }

        mappings[index].gitName = gitName
        mappings[index].gitEmail = gitEmail
        // 人工编辑后视为已复核
        aiPendingReviewUsernames.remove(svnUsername)
        refreshCoverage()
        state = .editing
    }

    /// 应用 AI 推断结果；写入映射后仍标记为待复核，直到用户再次编辑确认。
    public func applyAISuggestions(_ suggestions: [AIAuthorMappingSuggestion]) {
        for suggestion in suggestions {
            guard let index = mappings.firstIndex(where: { $0.svnUsername == suggestion.svnUsername }) else {
                continue
            }
            mappings[index].gitName = suggestion.gitName
            mappings[index].gitEmail = suggestion.gitEmail
            aiPendingReviewUsernames.insert(suggestion.svnUsername)
        }
        refreshCoverage()
        state = .editing
    }

    public func markAISuggestionReviewed(svnUsername: String) {
        aiPendingReviewUsernames.remove(svnUsername)
    }

    public func inferWithAI(
        emailDomain: String,
        privacySettings: AIPrivacySettings,
        inferrer: any AIAuthorMappingInferring
    ) async {
        state = .inferring
        do {
            let authors = mappings.map { GitMigrationAuthor(svnUsername: $0.svnUsername) }
            let draft = try await inferrer.inferMappings(
                authors: authors,
                emailDomain: emailDomain,
                privacySettings: privacySettings
            )
            applyAISuggestions(draft.suggestions)
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func exportAuthorsFile(to fileURL: URL) async {
        do {
            try mapper.exportAuthorsFile(mappings, to: fileURL)
            state = .exported(fileURL)
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func importAuthorsFile(from fileURL: URL) async {
        do {
            mappings = try mapper.importAuthorsFile(from: fileURL)
            aiPendingReviewUsernames = []
            refreshCoverage()
            state = .editing
        } catch {
            mappings = []
            aiPendingReviewUsernames = []
            refreshCoverage()
            state = .error(String(describing: error))
        }
    }

    private func refreshCoverage() {
        coverage = mapper.coverage(for: mappings)
    }
}
