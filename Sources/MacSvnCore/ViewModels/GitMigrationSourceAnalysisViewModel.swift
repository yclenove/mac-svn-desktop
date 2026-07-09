import Foundation
import Observation

public protocol GitMigrationSourceAnalyzing: Sendable {
    func analyze(repositoryRoot: String, auth: Credential?) async throws -> GitMigrationSourceAnalysis
}

public enum GitMigrationSourceAnalysisState: Equatable, Sendable {
    case idle
    case analyzing
    case completed(GitMigrationSourceAnalysis)
    case error(String)
}

@MainActor
@Observable
public final class GitMigrationSourceAnalysisViewModel {
    private let provider: any GitMigrationSourceAnalyzing

    public private(set) var state: GitMigrationSourceAnalysisState = .idle
    public private(set) var analysis: GitMigrationSourceAnalysis?

    public init(provider: any GitMigrationSourceAnalyzing) {
        self.provider = provider
    }

    public func analyze(repositoryRoot: String, auth: Credential? = nil) async {
        let normalizedRoot = repositoryRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRoot.isEmpty else {
            analysis = nil
            state = .error(String(describing: GitMigrationSourceAnalysisError.emptyRepositoryRoot))
            return
        }

        state = .analyzing
        analysis = nil

        do {
            let completedAnalysis = try await provider.analyze(repositoryRoot: normalizedRoot, auth: auth)
            analysis = completedAnalysis
            state = .completed(completedAnalysis)
        } catch {
            state = .error(String(describing: error))
        }
    }
}

extension GitMigrationSourceAnalyzer: GitMigrationSourceAnalyzing {}
