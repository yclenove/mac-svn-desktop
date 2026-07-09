import Foundation

public enum FinderSyncBadge: String, Equatable, Sendable {
    case normal
    case modified
    case added
    case deleted
    case missing
    case conflicted
    case replaced
    case unversioned
    case ignored
    case external
    case incomplete
    case obstructed
}

public enum FinderSyncMenuActionID: String, Codable, Equatable, Hashable, Sendable {
    case update
    case commit
    case log
    case diff
    case revert
    case add
    case delete
    case resolve
}

public struct FinderSyncMenuAction: Equatable, Sendable {
    public let id: FinderSyncMenuActionID
    public let title: String
    public let isEnabled: Bool

    public init(id: FinderSyncMenuActionID, title: String, isEnabled: Bool) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
    }
}

public struct FinderSyncPresentation: Equatable, Sendable {
    public let targetPath: String
    public let badge: FinderSyncBadge
    public let menuActions: [FinderSyncMenuAction]

    public init(targetPath: String, badge: FinderSyncBadge, menuActions: [FinderSyncMenuAction]) {
        self.targetPath = targetPath
        self.badge = badge
        self.menuActions = menuActions
    }
}

public struct FinderSyncPresentationBuilder: Sendable {
    public init() {}

    public func presentation(for targetPath: String, statuses: [FileStatus]) -> FinderSyncPresentation {
        let normalizedTarget = Self.normalize(targetPath)
        let matchedStatuses = Self.statusesMatching(targetPath: normalizedTarget, statuses: statuses)
        let badge = matchedStatuses
            .map(Self.badge)
            .sorted { Self.priority($0) > Self.priority($1) }
            .first ?? .normal

        return FinderSyncPresentation(
            targetPath: normalizedTarget,
            badge: badge,
            menuActions: []
        )
    }

    private static func statusesMatching(targetPath: String, statuses: [FileStatus]) -> [FileStatus] {
        statuses.filter { status in
            let path = normalize(status.path)
            return path == targetPath || path.hasPrefix(targetPath + "/")
        }
    }

    private static func badge(for status: FileStatus) -> FinderSyncBadge {
        if status.isTreeConflict {
            return .conflicted
        }

        switch status.itemStatus {
        case .normal, .none:
            return .normal
        case .modified:
            return .modified
        case .added:
            return .added
        case .deleted:
            return .deleted
        case .missing:
            return .missing
        case .conflicted:
            return .conflicted
        case .replaced:
            return .replaced
        case .unversioned:
            return .unversioned
        case .ignored:
            return .ignored
        case .external:
            return .external
        case .incomplete:
            return .incomplete
        case .obstructed:
            return .obstructed
        }
    }

    private static func priority(_ badge: FinderSyncBadge) -> Int {
        switch badge {
        case .conflicted:
            return 100
        case .modified, .replaced, .deleted, .missing, .added:
            return 80
        case .obstructed, .incomplete:
            return 70
        case .unversioned:
            return 60
        case .ignored, .external:
            return 20
        case .normal:
            return 0
        }
    }

    private static func normalize(_ path: String) -> String {
        path.split(separator: "/").joined(separator: "/")
    }
}
