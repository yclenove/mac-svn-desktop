import Foundation
import Observation

public enum GitMigrationAuthorMappingState: Equatable, Sendable {
    case idle
    case editing
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

    public var canStartMigration: Bool {
        coverage.isComplete
    }

    public init(mapper: GitMigrationAuthorMapper) {
        self.mapper = mapper
    }

    public func loadAuthors(_ authors: [GitMigrationAuthor]) {
        mappings = mapper.draftMappings(from: authors)
        refreshCoverage()
        state = .editing
    }

    public func updateMapping(svnUsername: String, gitName: String, gitEmail: String) {
        guard let index = mappings.firstIndex(where: { $0.svnUsername == svnUsername }) else {
            return
        }

        mappings[index].gitName = gitName
        mappings[index].gitEmail = gitEmail
        refreshCoverage()
        state = .editing
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
            refreshCoverage()
            state = .editing
        } catch {
            mappings = []
            refreshCoverage()
            state = .error(String(describing: error))
        }
    }

    private func refreshCoverage() {
        coverage = mapper.coverage(for: mappings)
    }
}
