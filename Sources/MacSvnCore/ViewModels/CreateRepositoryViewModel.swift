import Foundation
import Observation

public enum CreateRepositoryState: Equatable, Sendable {
    case idle
    case creating
    case completed(URL)
    case error(String)
}

@MainActor
@Observable
public final class CreateRepositoryViewModel {
    private let provider: any RepositoryCreating

    public private(set) var state: CreateRepositoryState = .idle

    public init(provider: any RepositoryCreating) {
        self.provider = provider
    }

    public func create(path: String) async {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            state = .error("emptyRepositoryPath")
            return
        }

        let destination = URL(fileURLWithPath: path).standardizedFileURL
        state = .creating
        do {
            try await provider.create(at: destination)
            state = .completed(destination)
        } catch {
            state = .error(String(describing: error))
        }
    }
}
