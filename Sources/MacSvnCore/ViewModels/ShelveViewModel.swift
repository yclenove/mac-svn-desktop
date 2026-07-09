import Foundation
import Observation

public protocol ShelveProviding: Sendable {
    func load() async throws -> [ShelveSnapshot]
    func shelve(wc: URL, name: String, paths: [String]) async throws -> ShelveSnapshot
    func createSafetySnapshot(wc: URL, name: String, paths: [String]) async throws -> ShelveSnapshot
    func preview(_ snapshot: ShelveSnapshot) async throws -> String
    func restore(_ snapshot: ShelveSnapshot, deleteAfterRestore: Bool) async throws
    func delete(_ snapshot: ShelveSnapshot) async throws
}

public enum ShelveOperation: Equatable, Sendable {
    case shelve
    case safetySnapshot
    case preview
    case restore
    case delete
}

public enum ShelveViewState: Equatable, Sendable {
    case idle
    case loading
    case running(ShelveOperation)
    case loaded
    case completed(ShelveOperation)
    case error(String)
}

@MainActor
@Observable
public final class ShelveViewModel {
    private let workingCopy: URL
    private let shelveProvider: any ShelveProviding

    public private(set) var state: ShelveViewState = .idle
    public private(set) var snapshots: [ShelveSnapshot] = []
    public private(set) var previewText = ""

    public init(workingCopy: URL, shelveProvider: any ShelveProviding) {
        self.workingCopy = workingCopy
        self.shelveProvider = shelveProvider
    }

    public func load() async {
        state = .loading
        await refreshSnapshots(successState: .loaded)
    }

    public func shelve(name: String, paths: [String]) async {
        guard let trimmedName = validate(name: name, paths: paths) else {
            return
        }

        state = .running(.shelve)

        do {
            _ = try await shelveProvider.shelve(wc: workingCopy, name: trimmedName, paths: paths)
            await refreshSnapshots(successState: .completed(.shelve))
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func createSafetySnapshot(name: String, paths: [String]) async {
        guard let trimmedName = validate(name: name, paths: paths) else {
            return
        }

        state = .running(.safetySnapshot)

        do {
            _ = try await shelveProvider.createSafetySnapshot(wc: workingCopy, name: trimmedName, paths: paths)
            await refreshSnapshots(successState: .completed(.safetySnapshot))
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func preview(_ snapshot: ShelveSnapshot) async {
        state = .running(.preview)

        do {
            previewText = try await shelveProvider.preview(snapshot)
            state = .completed(.preview)
        } catch {
            previewText = ""
            state = .error(String(describing: error))
        }
    }

    public func restore(_ snapshot: ShelveSnapshot, deleteAfterRestore: Bool = true) async {
        state = .running(.restore)

        do {
            try await shelveProvider.restore(snapshot, deleteAfterRestore: deleteAfterRestore)
            await refreshSnapshots(successState: .completed(.restore))
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func delete(_ snapshot: ShelveSnapshot) async {
        state = .running(.delete)

        do {
            try await shelveProvider.delete(snapshot)
            await refreshSnapshots(successState: .completed(.delete))
        } catch {
            state = .error(String(describing: error))
        }
    }

    private func validate(name: String, paths: [String]) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            state = .error("emptyShelveName")
            return nil
        }

        guard !paths.isEmpty else {
            state = .error("noSelectedPaths")
            return nil
        }

        return trimmedName
    }

    private func refreshSnapshots(successState: ShelveViewState) async {
        do {
            snapshots = try await shelveProvider.load()
            state = successState
        } catch {
            snapshots = []
            state = .error(String(describing: error))
        }
    }
}

extension ShelveService: ShelveProviding {}
