import Foundation
import Observation

public protocol ConflictListing: Sendable {
    func conflicts(wc: URL) async throws -> [ConflictInfo]
}

public protocol ConflictBatchResolving: Sendable {
    func resolve(wc: URL, paths: [String], accept: ResolveAccept) async throws -> ConflictBatchResolveOutcome
}

public enum ConflictListState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case resolving
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
    private let batchResolver: (any ConflictBatchResolving)?

    public private(set) var state: ConflictListState = .idle
    public private(set) var conflicts: [ConflictInfo] = []
    public private(set) var selectedConflictPath: String?
    /// 勾选用于批量 Resolved（#12）。
    public private(set) var checkedPaths: Set<String> = []
    public var kindFilter: ConflictKindFilter = .all
    public var searchText = ""

    public init(
        workingCopy: URL,
        provider: any ConflictListing,
        batchResolver: (any ConflictBatchResolving)? = nil
    ) {
        self.workingCopy = workingCopy
        self.provider = provider
        self.batchResolver = batchResolver ?? (provider as? any ConflictBatchResolving)
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

    /// 当前勾选中可批量标记已解决的路径。
    public var checkedPathsEligibleForMarkResolved: [String] {
        ConflictResolveBatchPolicy.filterCheckedPaths(checked: checkedPaths, conflicts: conflicts)
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
            let previousChecked = checkedPaths
            conflicts = try await provider.conflicts(wc: workingCopy)
            let existing = Set(conflicts.map(\.path))
            checkedPaths = previousChecked.intersection(existing)
            if let previousSelection, existing.contains(previousSelection) {
                selectedConflictPath = previousSelection
            } else {
                selectedConflictPath = conflicts.first?.path
            }
            state = .loaded
        } catch {
            conflicts = []
            selectedConflictPath = nil
            checkedPaths = []
            state = .error(String(describing: error))
        }
    }

    public func selectConflict(path: String) {
        guard conflicts.contains(where: { $0.path == path }) else {
            return
        }

        selectedConflictPath = path
    }

    public func setChecked(_ path: String, isChecked: Bool) {
        guard conflicts.contains(where: { $0.path == path }) else { return }
        if isChecked {
            checkedPaths.insert(path)
        } else {
            checkedPaths.remove(path)
        }
    }

    public func toggleChecked(_ path: String) {
        setChecked(path, isChecked: !checkedPaths.contains(path))
    }

    public func checkAllVisibleEligible() {
        for conflict in visibleConflicts where ConflictResolveBatchPolicy.isEligibleForMarkResolved(conflict) {
            checkedPaths.insert(conflict.path)
        }
    }

    public func clearChecked() {
        checkedPaths = []
    }

    /// 批量 `svn resolve --accept working`（#12）。返回成功件数；部分失败时 state 带摘要。
    public func markCheckedAsResolved() async -> Int {
        guard let batchResolver else {
            state = .error("batchResolverUnavailable")
            return 0
        }
        let paths = checkedPathsEligibleForMarkResolved
        guard !paths.isEmpty else { return 0 }

        state = .resolving
        do {
            let outcome = try await batchResolver.resolve(wc: workingCopy, paths: paths, accept: .working)
            await refresh()
            if outcome.hasFailures {
                let detail = outcome.errorSummaries.joined(separator: "; ")
                state = .error("部分成功 \(outcome.succeededCount)/\(paths.count)：\(detail)")
            }
            return outcome.succeededCount
        } catch {
            state = .error(String(describing: error))
            return 0
        }
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
extension ConflictService: ConflictBatchResolving {}
