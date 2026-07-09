import Observation

public enum BranchBrowserState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

@MainActor
@Observable
public final class BranchBrowserViewModel {
    private let provider: any BranchListProviding

    public private(set) var state: BranchBrowserState = .idle
    public private(set) var branchList = BranchList()

    public init(provider: any BranchListProviding) {
        self.provider = provider
    }

    public func load(
        repositoryRoot: String,
        layout: BranchLayout,
        auth: Credential? = nil
    ) async {
        state = .loading

        do {
            branchList = try await provider.branches(
                repositoryRoot: repositoryRoot,
                layout: layout,
                auth: auth
            )
            state = .loaded
        } catch {
            branchList = BranchList()
            state = .error(String(describing: error))
        }
    }
}
