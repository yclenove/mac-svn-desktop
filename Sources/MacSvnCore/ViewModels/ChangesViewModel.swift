import Foundation
import Observation

public protocol StatusProviding: Sendable {
    func status(wc: URL) async throws -> [FileStatus]
}

public enum ChangesDisplayMode: Equatable, Sendable {
    case tree
    case flat
}

public enum StatusFilter: Equatable, Sendable {
    case all
    case items(Set<ItemStatus>)
    case conflicts
}

public enum ChangesViewState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

public struct FileStatusNode: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let itemStatus: ItemStatus
    public let isTreeConflict: Bool
    public let isDirectory: Bool
    public let fileStatus: FileStatus?
    public let children: [FileStatusNode]

    public init(
        id: String,
        name: String,
        path: String,
        itemStatus: ItemStatus,
        isTreeConflict: Bool,
        isDirectory: Bool,
        fileStatus: FileStatus?,
        children: [FileStatusNode]
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.itemStatus = itemStatus
        self.isTreeConflict = isTreeConflict
        self.isDirectory = isDirectory
        self.fileStatus = fileStatus
        self.children = children
    }
}

public enum FileStatusListBuilder {
    public static func flatEntries(
        from statuses: [FileStatus],
        filter: StatusFilter,
        searchText: String
    ) -> [FileStatus] {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return statuses.filter { status in
            matches(status, filter: filter) && matches(status.path, searchText: normalizedSearch)
        }
    }

    public static func tree(from statuses: [FileStatus]) -> [FileStatusNode] {
        makeNodes(from: statuses, depth: 0, prefix: [])
    }

    private static func matches(_ status: FileStatus, filter: StatusFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .items(let statuses):
            return statuses.contains(status.itemStatus)
        case .conflicts:
            return status.itemStatus == .conflicted || status.isTreeConflict
        }
    }

    private static func matches(_ path: String, searchText: String) -> Bool {
        guard !searchText.isEmpty else {
            return true
        }

        return (path as NSString).lastPathComponent.lowercased().contains(searchText)
    }

    private static func makeNodes(from statuses: [FileStatus], depth: Int, prefix: [String]) -> [FileStatusNode] {
        let grouped = Dictionary(grouping: statuses) { status in
            components(for: status.path)[depth]
        }

        return grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { component in
            let matchingStatuses = grouped[component, default: []]
            let exactStatus = matchingStatuses.first { components(for: $0.path).count == depth + 1 }
            let descendantStatuses = matchingStatuses.filter { components(for: $0.path).count > depth + 1 }
            let nodeComponents = prefix + [component]
            let path = nodeComponents.joined(separator: "/")

            guard !descendantStatuses.isEmpty else {
                let status = exactStatus ?? matchingStatuses[0]
                return FileStatusNode(
                    id: path,
                    name: component,
                    path: path,
                    itemStatus: status.itemStatus,
                    isTreeConflict: status.isTreeConflict,
                    isDirectory: false,
                    fileStatus: status,
                    children: []
                )
            }

            let children = makeNodes(from: descendantStatuses, depth: depth + 1, prefix: nodeComponents)
            return FileStatusNode(
                id: path,
                name: component,
                path: path,
                itemStatus: aggregateStatus(from: matchingStatuses),
                isTreeConflict: matchingStatuses.contains { $0.isTreeConflict },
                isDirectory: true,
                fileStatus: exactStatus,
                children: children
            )
        }
    }

    private static func components(for path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }

    private static func aggregateStatus(from statuses: [FileStatus]) -> ItemStatus {
        if statuses.contains(where: { $0.itemStatus == .conflicted || $0.isTreeConflict }) {
            return .conflicted
        }

        return statuses
            .map(\.itemStatus)
            .min { priority($0) < priority($1) } ?? .normal
    }

    private static func priority(_ status: ItemStatus) -> Int {
        switch status {
        case .conflicted:
            return 0
        case .modified:
            return 1
        case .added:
            return 2
        case .deleted:
            return 3
        case .missing:
            return 4
        case .replaced:
            return 5
        case .unversioned:
            return 6
        case .ignored:
            return 7
        case .external:
            return 8
        case .incomplete:
            return 9
        case .obstructed:
            return 10
        case .normal:
            return 11
        case .none:
            return 12
        }
    }
}

@MainActor
@Observable
public final class ChangesViewModel {
    private let workingCopy: URL
    private let statusProvider: any StatusProviding

    public private(set) var state: ChangesViewState = .idle
    public private(set) var entries: [FileStatus] = []
    public var displayMode: ChangesDisplayMode = .tree
    public var filter: StatusFilter = .all
    public var searchText = ""

    public init(workingCopy: URL, statusProvider: any StatusProviding) {
        self.workingCopy = workingCopy
        self.statusProvider = statusProvider
    }

    public var visibleFlatEntries: [FileStatus] {
        FileStatusListBuilder.flatEntries(from: entries, filter: filter, searchText: searchText)
    }

    public var visibleTreeEntries: [FileStatusNode] {
        FileStatusListBuilder.tree(from: visibleFlatEntries)
    }

    public func refresh() async {
        state = .loading

        do {
            entries = try await statusProvider.status(wc: workingCopy)
            state = .loaded
        } catch {
            entries = []
            state = .error(String(describing: error))
        }
    }
}

extension SvnService: StatusProviding {}
