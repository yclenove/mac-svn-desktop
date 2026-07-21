import Foundation
import Observation

public protocol BranchCopyProviding: Sendable {
    func copy(source: String, destination: String, message: String, auth: Credential?) async throws -> Revision
}

public enum BranchCopySource: Equatable, Sendable {
    case head(repositoryURL: String)
    case revision(repositoryURL: String, revision: Revision)
    case workingCopy(URL)

    public var commandSource: String {
        switch self {
        case .head(let repositoryURL):
            return LogContextActionPolicy.stripPegRevision(from: repositoryURL)
        case .revision(let repositoryURL, let revision):
            let url = LogContextActionPolicy.stripPegRevision(from: repositoryURL)
            return "\(url)@\(revision.value)"
        case .workingCopy(let url):
            return url.path
        }
    }
}

public enum BranchCopyState: Equatable, Sendable {
    case idle
    case copying
    case completed(Revision)
    case error(String)
}

@MainActor
@Observable
public final class BranchCopyViewModel {
    private let copyProvider: any BranchCopyProviding

    public private(set) var state: BranchCopyState = .idle
    public private(set) var createdRevision: Revision?

    public init(copyProvider: any BranchCopyProviding) {
        self.copyProvider = copyProvider
    }

    public func create(
        kind: BranchReferenceKind,
        source: BranchCopySource,
        repositoryRoot: String,
        name: String,
        layout: BranchLayout,
        message: String,
        auth: Credential? = nil
    ) async {
        await create(
            kind: kind,
            source: source.commandSource,
            repositoryRoot: repositoryRoot,
            name: name,
            layout: layout,
            message: message,
            auth: auth
        )
    }

    public func create(
        kind: BranchReferenceKind,
        source: String,
        repositoryRoot: String,
        name: String,
        layout: BranchLayout,
        message: String,
        auth: Credential? = nil
    ) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            createdRevision = nil
            state = .error("emptyBranchName")
            return
        }

        guard let parentPath = parentPath(for: kind, layout: layout) else {
            createdRevision = nil
            state = .error("unsupportedBranchCopyKind")
            return
        }

        state = .copying

        do {
            let destinationParent = BranchListURLResolver.url(repositoryRoot: repositoryRoot, path: parentPath)
            let destination = BranchListURLResolver.url(repositoryRoot: destinationParent, path: trimmedName)
            let revision = try await copyProvider.copy(
                source: source,
                destination: destination,
                message: message,
                auth: auth
            )
            createdRevision = revision
            state = .completed(revision)
        } catch {
            createdRevision = nil
            state = .error(String(describing: error))
        }
    }

    private func parentPath(for kind: BranchReferenceKind, layout: BranchLayout) -> String? {
        switch kind {
        case .branch:
            return layout.branches
        case .tag:
            return layout.tags
        case .trunk:
            return nil
        }
    }
}

extension SvnService: BranchCopyProviding {}
