import Foundation

public protocol GitMigrationEnvironmentChecking: Sendable {
    func check() async throws -> GitMigrationEnvironmentStatus
}

public protocol GitMigrationSourceListing: Sendable {
    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry]
}

public protocol GitMigrationSourceLogging: Sendable {
    func remoteLogFromHead(url: String, batch: Int, verbose: Bool, auth: Credential?) async throws -> [LogEntry]
}

public struct GitMigrationSourceAnalyzer: Sendable {
    private let environmentChecker: any GitMigrationEnvironmentChecking
    private let listProvider: any GitMigrationSourceListing
    private let logProvider: any GitMigrationSourceLogging

    public init(
        environmentChecker: any GitMigrationEnvironmentChecking,
        listProvider: any GitMigrationSourceListing,
        logProvider: any GitMigrationSourceLogging
    ) {
        self.environmentChecker = environmentChecker
        self.listProvider = listProvider
        self.logProvider = logProvider
    }

    public func analyze(
        repositoryRoot: String,
        auth: Credential? = nil
    ) async throws -> GitMigrationSourceAnalysis {
        let normalizedRoot = repositoryRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRoot.isEmpty else {
            throw GitMigrationSourceAnalysisError.emptyRepositoryRoot
        }

        let environment = try await environmentChecker.check()
        let entries = try await listProvider.list(url: normalizedRoot, depth: .immediates, auth: auth)
        let logs = try await logProvider.remoteLogFromHead(
            url: normalizedRoot,
            batch: Int.max,
            verbose: false,
            auth: auth
        )

        let revisions = logs.map(\.revision).sorted { $0.value < $1.value }
        return GitMigrationSourceAnalysis(
            repositoryRoot: normalizedRoot,
            environment: environment,
            layout: Self.layout(from: entries),
            authors: Self.authors(from: logs),
            latestRevision: revisions.last,
            oldestRevision: revisions.first,
            totalRevisionCount: revisions.count,
            sourceRevisions: revisions
        )
    }

    private static func layout(from entries: [RemoteEntry]) -> GitMigrationRepositoryLayout {
        let directoryNames = Set(entries.compactMap { entry -> String? in
            guard entry.kind == .directory else {
                return nil
            }
            return entry.name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        })

        if directoryNames.isSuperset(of: ["trunk", "branches", "tags"]) {
            return GitMigrationRepositoryLayout(
                kind: .standard,
                trunkPath: "trunk",
                branchesPath: "branches",
                tagsPath: "tags",
                confidence: 1.0
            )
        }

        return GitMigrationRepositoryLayout(
            kind: .custom,
            trunkPath: nil,
            branchesPath: nil,
            tagsPath: nil,
            confidence: 0
        )
    }

    private static func authors(from logs: [LogEntry]) -> [GitMigrationAuthor] {
        let usernames = Set(logs.compactMap { entry -> String? in
            let username = entry.author.trimmingCharacters(in: .whitespacesAndNewlines)
            return username.isEmpty ? nil : username
        })

        return usernames
            .sorted()
            .map(GitMigrationAuthor.init(svnUsername:))
    }
}

extension GitMigrationEnvironmentChecker: GitMigrationEnvironmentChecking {}
extension SvnService: GitMigrationSourceListing {}
extension SvnService: GitMigrationSourceLogging {}
