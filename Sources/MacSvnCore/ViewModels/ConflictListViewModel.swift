import Foundation
import Observation

public protocol ConflictListing: Sendable {
    func conflicts(wc: URL) async throws -> [ConflictInfo]
}

public enum ConflictListState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

public enum ConflictKindFilter: Equatable, Sendable {
    case all
    case kinds(Set<ConflictKind>)
}

public struct ConflictListSummary: Equatable, Sendable {
    public let total: Int
    public let text: Int
    public let tree: Int
    public let property: Int
    public let unknown: Int

    public init(
        total: Int = 0,
        text: Int = 0,
        tree: Int = 0,
        property: Int = 0,
        unknown: Int = 0
    ) {
        self.total = total
        self.text = text
        self.tree = tree
        self.property = property
        self.unknown = unknown
    }
}

@MainActor
@Observable
public final class ConflictListViewModel {
    private let workingCopy: URL
    private let provider: any ConflictListing

    public private(set) var state: ConflictListState = .idle
    public private(set) var conflicts: [ConflictInfo] = []
    public private(set) var selectedConflictPath: String?
    public var kindFilter: ConflictKindFilter = .all
    public var searchText = ""

    public init(workingCopy: URL, provider: any ConflictListing) {
        self.workingCopy = workingCopy
        self.provider = provider
    }

    public var visibleConflicts: [ConflictInfo] {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return conflicts.filter { conflict in
            matches(conflict.kind) && matches(conflict.path, searchText: normalizedSearch)
        }
    }

    public var selectedConflict: ConflictInfo? {
        guard let selectedConflictPath else {
            return nil
        }

        return conflicts.first { $0.path == selectedConflictPath }
    }

    public var summary: ConflictListSummary {
        conflicts.reduce(into: ConflictListSummary()) { summary, conflict in
            summary = ConflictListSummary(
                total: summary.total + 1,
                text: summary.text + (conflict.kind == .text ? 1 : 0),
                tree: summary.tree + (conflict.kind == .tree ? 1 : 0),
                property: summary.property + (conflict.kind == .property ? 1 : 0),
                unknown: summary.unknown + (conflict.kind == .unknown ? 1 : 0)
            )
        }
    }

    public func refresh() async {
        state = .loading

        do {
            let previousSelection = selectedConflictPath
            conflicts = try await provider.conflicts(wc: workingCopy)
            if let previousSelection, conflicts.contains(where: { $0.path == previousSelection }) {
                selectedConflictPath = previousSelection
            } else {
                selectedConflictPath = conflicts.first?.path
            }
            state = .loaded
        } catch {
            conflicts = []
            selectedConflictPath = nil
            state = .error(String(describing: error))
        }
    }

    public func selectConflict(path: String) {
        guard conflicts.contains(where: { $0.path == path }) else {
            return
        }

        selectedConflictPath = path
    }

    private func matches(_ kind: ConflictKind) -> Bool {
        switch kindFilter {
        case .all:
            return true
        case .kinds(let kinds):
            return kinds.contains(kind)
        }
    }

    private func matches(_ path: String, searchText: String) -> Bool {
        guard !searchText.isEmpty else {
            return true
        }

        return path.lowercased().contains(searchText)
    }
}

extension ConflictService: ConflictListing {}
