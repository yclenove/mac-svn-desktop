import Foundation

public protocol BranchRepositoryListing: Sendable {
    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry]
}

public protocol BranchListProviding: Sendable {
    func branches(repositoryRoot: String, layout: BranchLayout, auth: Credential?) async throws -> BranchList
}

public enum BranchListURLResolver {
    public static func url(repositoryRoot: String, path: String) -> String {
        let normalizedRoot = repositoryRoot.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !normalizedPath.isEmpty else {
            return normalizedRoot
        }

        return normalizedRoot + "/" + normalizedPath
    }
}

public struct BranchListService: BranchListProviding {
    private let listProvider: any BranchRepositoryListing

    public init(listProvider: any BranchRepositoryListing) {
        self.listProvider = listProvider
    }

    public func branches(
        repositoryRoot: String,
        layout: BranchLayout,
        auth: Credential? = nil
    ) async throws -> BranchList {
        let trunkURL = BranchListURLResolver.url(repositoryRoot: repositoryRoot, path: layout.trunk)
        let branchesURL = BranchListURLResolver.url(repositoryRoot: repositoryRoot, path: layout.branches)
        let tagsURL = BranchListURLResolver.url(repositoryRoot: repositoryRoot, path: layout.tags)

        let trunk = try await trunkReference(url: trunkURL, auth: auth)
        let branches = try await references(
            baseURL: branchesURL,
            kind: .branch,
            auth: auth
        )
        let tags = try await references(
            baseURL: tagsURL,
            kind: .tag,
            auth: auth
        )

        return BranchList(trunk: trunk, branches: branches, tags: tags)
    }

    private func trunkReference(url: String, auth: Credential?) async throws -> BranchReference? {
        do {
            let entries = try await listProvider.list(url: url, depth: .immediates, auth: auth)
            let newestEntry = entries.compactMap { entry -> (RemoteEntry, Int)? in
                guard let revision = entry.revision?.value else {
                    return nil
                }
                return (entry, revision)
            }
            .max { lhs, rhs in lhs.1 < rhs.1 }?
            .0

            return BranchReference(
                name: "trunk",
                url: url,
                kind: .trunk,
                revision: newestEntry?.revision,
                author: newestEntry?.author,
                date: newestEntry?.date
            )
        } catch SvnError.environment {
            return nil
        }
    }

    private func references(
        baseURL: String,
        kind: BranchReferenceKind,
        auth: Credential?
    ) async throws -> [BranchReference] {
        let entries = try await listProvider.list(url: baseURL, depth: .immediates, auth: auth)

        return entries.compactMap { entry in
            guard entry.kind == .directory else {
                return nil
            }

            return BranchReference(
                name: entry.name,
                url: BranchListURLResolver.url(repositoryRoot: baseURL, path: entry.path),
                kind: kind,
                revision: entry.revision,
                author: entry.author,
                date: entry.date
            )
        }
    }
}

extension SvnService: BranchRepositoryListing {}

extension SvnService: BranchListProviding {
    public func branches(
        repositoryRoot: String,
        layout: BranchLayout,
        auth: Credential? = nil
    ) async throws -> BranchList {
        try await BranchListService(listProvider: self).branches(
            repositoryRoot: repositoryRoot,
            layout: layout,
            auth: auth
        )
    }
}
