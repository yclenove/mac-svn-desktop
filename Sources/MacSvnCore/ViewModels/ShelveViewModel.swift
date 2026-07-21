import Foundation
import Observation

public protocol ShelveProviding: Sendable {
    func load() async throws -> [ShelveSnapshot]
    func shelve(wc: URL, name: String, paths: [String]) async throws -> ShelveSnapshot
    func createSafetySnapshot(wc: URL, name: String, paths: [String]) async throws -> ShelveSnapshot
    func preview(_ snapshot: ShelveSnapshot) async throws -> String
    func restore(_ snapshot: ShelveSnapshot, deleteAfterRestore: Bool) async throws
    func delete(_ snapshot: ShelveSnapshot) async throws
    func officialAvailability(wc: URL) async -> SvnShelvingAvailability
    func officialShelves(wc: URL) async throws -> [SvnShelf]
    func officialShelve(wc: URL, name: String, paths: [String], message: String, keepLocal: Bool) async throws
    func officialDiff(wc: URL, name: String, version: Int?) async throws -> String
    func officialLog(wc: URL, name: String) async throws -> String
    func officialUnshelve(wc: URL, name: String, version: Int?, drop: Bool) async throws
    func officialDrop(wc: URL, name: String) async throws
    func migrateToOfficial(_ snapshot: ShelveSnapshot) async throws
}

public extension ShelveProviding {
    func officialAvailability(wc: URL) async -> SvnShelvingAvailability {
        .unavailable(.v3, reason: "official shelving provider is not configured")
    }

    func officialShelves(wc: URL) async throws -> [SvnShelf] {
        throw ShelveServiceError.officialUnavailable
    }

    func officialShelve(wc: URL, name: String, paths: [String], message: String, keepLocal: Bool) async throws {
        throw ShelveServiceError.officialUnavailable
    }

    func officialDiff(wc: URL, name: String, version: Int?) async throws -> String {
        throw ShelveServiceError.officialUnavailable
    }

    func officialLog(wc: URL, name: String) async throws -> String {
        throw ShelveServiceError.officialUnavailable
    }

    func officialUnshelve(wc: URL, name: String, version: Int?, drop: Bool) async throws {
        throw ShelveServiceError.officialUnavailable
    }

    func officialDrop(wc: URL, name: String) async throws {
        throw ShelveServiceError.officialUnavailable
    }

    func migrateToOfficial(_ snapshot: ShelveSnapshot) async throws {
        throw ShelveServiceError.officialUnavailable
    }
}

public enum ShelveOperation: Equatable, Sendable {
    case shelve
    case safetySnapshot
    case preview
    case restore
    case delete
    case officialShelve
    case officialDiff
    case officialLog
    case officialUnshelve
    case officialDrop
    case migrate
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
    public private(set) var officialAvailability: SvnShelvingAvailability?
    public private(set) var officialShelves: [SvnShelf] = []
    public private(set) var officialDiffText = ""
    public private(set) var officialLogText = ""
    public private(set) var officialError: String?
    private var operationGeneration = 0

    public init(workingCopy: URL, shelveProvider: any ShelveProviding) {
        self.workingCopy = workingCopy
        self.shelveProvider = shelveProvider
    }

    public func load() async {
        let generation = beginOperation(.loading)
        await refreshSnapshots(
            successState: .loading,
            generation: generation,
            expectedState: .loading
        )
        guard generation == operationGeneration, state == .loading else { return }
        await refreshOfficial(generation: generation, expectedState: .loading)
        guard generation == operationGeneration, state == .loading else { return }
        state = .loaded
    }

    public func shelve(name: String, paths: [String]) async {
        beginOperation(.running(.shelve))
        guard let trimmedName = validate(name: name, paths: paths) else {
            return
        }

        do {
            _ = try await shelveProvider.shelve(wc: workingCopy, name: trimmedName, paths: paths)
            await refreshSnapshots(successState: .completed(.shelve))
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func createSafetySnapshot(name: String, paths: [String]) async {
        beginOperation(.running(.safetySnapshot))
        guard let trimmedName = validate(name: name, paths: paths) else {
            return
        }

        do {
            _ = try await shelveProvider.createSafetySnapshot(wc: workingCopy, name: trimmedName, paths: paths)
            await refreshSnapshots(successState: .completed(.safetySnapshot))
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func preview(_ snapshot: ShelveSnapshot) async {
        beginOperation(.running(.preview))

        do {
            previewText = try await shelveProvider.preview(snapshot)
            state = .completed(.preview)
        } catch {
            previewText = ""
            state = .error(String(describing: error))
        }
    }

    public func restore(_ snapshot: ShelveSnapshot, deleteAfterRestore: Bool = true) async {
        beginOperation(.running(.restore))

        do {
            try await shelveProvider.restore(snapshot, deleteAfterRestore: deleteAfterRestore)
            await refreshSnapshots(successState: .completed(.restore))
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func delete(_ snapshot: ShelveSnapshot) async {
        beginOperation(.running(.delete))

        do {
            try await shelveProvider.delete(snapshot)
            await refreshSnapshots(successState: .completed(.delete))
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func officialShelve(
        name: String,
        paths: [String],
        message: String = "",
        keepLocal: Bool = false
    ) async {
        beginOperation(.running(.officialShelve))
        guard let trimmedName = validate(name: name, paths: paths) else { return }

        do {
            try await shelveProvider.officialShelve(
                wc: workingCopy,
                name: trimmedName,
                paths: paths,
                message: message,
                keepLocal: keepLocal
            )
            await refreshOfficial()
            state = .completed(.officialShelve)
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func officialDiff(_ shelf: SvnShelf, version: Int? = nil) async {
        beginOperation(.running(.officialDiff))
        do {
            officialDiffText = try await shelveProvider.officialDiff(
                wc: workingCopy,
                name: shelf.name,
                version: version ?? shelf.latestVersion
            )
            state = .completed(.officialDiff)
        } catch {
            officialDiffText = ""
            state = .error(String(describing: error))
        }
    }

    public func officialLog(_ shelf: SvnShelf) async {
        beginOperation(.running(.officialLog))
        do {
            officialLogText = try await shelveProvider.officialLog(wc: workingCopy, name: shelf.name)
            state = .completed(.officialLog)
        } catch {
            officialLogText = ""
            state = .error(String(describing: error))
        }
    }

    public func officialUnshelve(_ shelf: SvnShelf, version: Int? = nil, drop: Bool = false) async {
        beginOperation(.running(.officialUnshelve))
        do {
            try await shelveProvider.officialUnshelve(
                wc: workingCopy,
                name: shelf.name,
                version: version ?? shelf.latestVersion,
                drop: drop
            )
            await refreshOfficial()
            state = .completed(.officialUnshelve)
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func officialDrop(_ shelf: SvnShelf) async {
        beginOperation(.running(.officialDrop))
        do {
            try await shelveProvider.officialDrop(wc: workingCopy, name: shelf.name)
            await refreshOfficial()
            state = .completed(.officialDrop)
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func migrateToOfficial(_ snapshot: ShelveSnapshot) async {
        let generation = beginOperation(.running(.migrate))
        do {
            try await shelveProvider.migrateToOfficial(snapshot)
            await refreshSnapshots(
                successState: .running(.migrate),
                generation: generation,
                expectedState: .running(.migrate)
            )
            guard generation == operationGeneration, state == .running(.migrate) else { return }
            await refreshOfficial(
                generation: generation,
                expectedState: .running(.migrate)
            )
            guard generation == operationGeneration, state == .running(.migrate) else { return }
            state = .completed(.migrate)
        } catch {
            guard generation == operationGeneration, state == .running(.migrate) else { return }
            state = .error(String(describing: error))
        }
    }

    @discardableResult
    private func beginOperation(_ newState: ShelveViewState) -> Int {
        operationGeneration += 1
        state = newState
        return operationGeneration
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

    private func refreshSnapshots(
        successState: ShelveViewState,
        generation: Int? = nil,
        expectedState: ShelveViewState? = nil
    ) async {
        do {
            let loadedSnapshots = try await shelveProvider.load()
            guard canCommitOperationResult(
                generation: generation,
                expectedState: expectedState
            ) else { return }
            snapshots = loadedSnapshots
            state = successState
        } catch {
            guard canCommitOperationResult(
                generation: generation,
                expectedState: expectedState
            ) else { return }
            snapshots = []
            state = .error(String(describing: error))
        }
    }

    private func canCommitOperationResult(
        generation: Int?,
        expectedState: ShelveViewState?
    ) -> Bool {
        if let generation, generation != operationGeneration {
            return false
        }
        if let expectedState, state != expectedState {
            return false
        }
        return true
    }

    private func refreshOfficial(
        generation: Int? = nil,
        expectedState: ShelveViewState? = nil
    ) async {
        let loadedAvailability = await shelveProvider.officialAvailability(wc: workingCopy)
        var loadedShelves: [SvnShelf] = []
        var loadError: String?
        if case .available = loadedAvailability {
            do {
                loadedShelves = try await shelveProvider.officialShelves(wc: workingCopy)
            } catch {
                loadError = String(describing: error)
            }
        }
        guard canCommitOperationResult(
            generation: generation,
            expectedState: expectedState
        ) else { return }
        officialAvailability = loadedAvailability
        officialShelves = loadedShelves
        officialError = loadError
    }
}

extension ShelveService: ShelveProviding {}
