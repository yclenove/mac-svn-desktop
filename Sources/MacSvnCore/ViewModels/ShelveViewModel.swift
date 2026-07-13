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

    public init(workingCopy: URL, shelveProvider: any ShelveProviding) {
        self.workingCopy = workingCopy
        self.shelveProvider = shelveProvider
    }

    public func load() async {
        state = .loading
        await refreshSnapshots(successState: .loaded)
        guard state == .loaded else { return }
        await refreshOfficial()
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

    public func officialShelve(
        name: String,
        paths: [String],
        message: String = "",
        keepLocal: Bool = false
    ) async {
        guard let trimmedName = validate(name: name, paths: paths) else { return }
        state = .running(.officialShelve)

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
        state = .running(.officialDiff)
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
        state = .running(.officialLog)
        do {
            officialLogText = try await shelveProvider.officialLog(wc: workingCopy, name: shelf.name)
            state = .completed(.officialLog)
        } catch {
            officialLogText = ""
            state = .error(String(describing: error))
        }
    }

    public func officialUnshelve(_ shelf: SvnShelf, version: Int? = nil, drop: Bool = false) async {
        state = .running(.officialUnshelve)
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
        state = .running(.officialDrop)
        do {
            try await shelveProvider.officialDrop(wc: workingCopy, name: shelf.name)
            await refreshOfficial()
            state = .completed(.officialDrop)
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func migrateToOfficial(_ snapshot: ShelveSnapshot) async {
        state = .running(.migrate)
        do {
            try await shelveProvider.migrateToOfficial(snapshot)
            await refreshSnapshots(successState: .completed(.migrate))
            guard state == .completed(.migrate) else { return }
            await refreshOfficial()
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

    private func refreshOfficial() async {
        officialAvailability = await shelveProvider.officialAvailability(wc: workingCopy)
        officialError = nil
        guard case .available = officialAvailability else {
            officialShelves = []
            return
        }

        do {
            officialShelves = try await shelveProvider.officialShelves(wc: workingCopy)
        } catch {
            officialShelves = []
            officialError = String(describing: error)
        }
    }
}

extension ShelveService: ShelveProviding {}
