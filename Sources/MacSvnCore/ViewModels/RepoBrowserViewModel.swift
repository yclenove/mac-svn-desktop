import Foundation
import Observation

public protocol RepoListProviding: Sendable {
    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry]
}

public enum RepoBrowserState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

@MainActor
@Observable
public final class RepoBrowserViewModel {
    private let listProvider: any RepoListProviding

    private var statesByURL: [String: RepoBrowserState] = [:]
    private var childrenByURL: [String: [RemoteEntry]] = [:]

    public init(listProvider: any RepoListProviding) {
        self.listProvider = listProvider
    }

    public func state(for url: String) -> RepoBrowserState {
        statesByURL[url, default: .idle]
    }

    public func children(of url: String) -> [RemoteEntry] {
        childrenByURL[url, default: []]
    }

    public func loadChildren(of url: String, auth: Credential? = nil) async {
        statesByURL[url] = .loading

        do {
            childrenByURL[url] = try await listProvider.list(url: url, depth: .immediates, auth: auth)
            statesByURL[url] = .loaded
        } catch {
            childrenByURL[url] = []
            statesByURL[url] = .error(String(describing: error))
        }
    }
}

extension SvnService: RepoListProviding {}
