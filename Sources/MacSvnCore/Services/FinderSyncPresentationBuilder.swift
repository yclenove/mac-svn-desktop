import Foundation

public enum FinderSyncBadge: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
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
    case locked
    case needsLock
    case shallow
    case nested
    case switched
    case mergeInfo

    public var displayName: String {
        switch self {
        case .normal: return "正常"
        case .modified: return "已修改"
        case .added: return "已添加"
        case .deleted: return "已删除"
        case .missing: return "缺失"
        case .conflicted: return "冲突"
        case .replaced: return "已替换"
        case .unversioned: return "未版本控制"
        case .ignored: return "已忽略"
        case .external: return "外部项"
        case .incomplete: return "不完整"
        case .obstructed: return "阻碍"
        case .locked: return "已锁定"
        case .needsLock: return "需要锁定"
        case .shallow: return "稀疏深度"
        case .nested: return "嵌套工作副本"
        case .switched: return "已切换"
        case .mergeInfo: return "仅合并信息"
        }
    }
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

    public func presentation(
        for targetPath: String,
        statuses: [FileStatus],
        overlaySettings: FinderSyncOverlaySettings = FinderSyncOverlaySettings()
    ) -> FinderSyncPresentation {
        let normalizedTarget = Self.normalize(targetPath)
        let matchedStatuses = Self.statusesMatching(targetPath: normalizedTarget, statuses: statuses)
        let dominantStatus = matchedStatuses.sorted {
            Self.priority(Self.badge(for: $0, enabledBadges: overlaySettings.enabledBadges))
                > Self.priority(Self.badge(for: $1, enabledBadges: overlaySettings.enabledBadges))
        }.first
        let badge = dominantStatus.map {
            Self.badge(for: $0, enabledBadges: overlaySettings.enabledBadges)
        } ?? .normal

        return FinderSyncPresentation(
            targetPath: normalizedTarget,
            badge: badge,
            menuActions: Self.menuActions(for: dominantStatus)
        )
    }

    private static func statusesMatching(targetPath: String, statuses: [FileStatus]) -> [FileStatus] {
        if targetPath == "." {
            return statuses
        }
        return statuses.filter { status in
            let path = normalize(status.path)
            return path == targetPath || path.hasPrefix(targetPath + "/")
        }
    }

    private static func badge(
        for status: FileStatus,
        enabledBadges: Set<FinderSyncBadge> = Set(FinderSyncBadge.allCases)
    ) -> FinderSyncBadge {
        badges(for: status)
            .filter(enabledBadges.contains)
            .max { priority($0) < priority($1) }
            ?? .normal
    }

    private static func badges(for status: FileStatus) -> [FinderSyncBadge] {
        var badges: [FinderSyncBadge] = [baseBadge(for: status)]
        let overlay = status.overlay
        if overlay.propertyStatus == .conflicted {
            badges.append(.conflicted)
        } else if overlay.propertyStatus != .none,
                  overlay.propertyStatus != .normal,
                  !overlay.isMergeInfoOnly {
            badges.append(.modified)
        }
        if overlay.isWorkingCopyLocked || overlay.isRepositoryLocked {
            badges.append(.locked)
        }
        if overlay.hasNeedsLock && overlay.isReadOnly {
            badges.append(.needsLock)
        }
        if let depth = overlay.depth, depth != .infinity {
            badges.append(.shallow)
        }
        if overlay.isNestedWorkingCopy {
            badges.append(.nested)
        }
        if overlay.isSwitched {
            badges.append(.switched)
        }
        if overlay.isFileExternal || status.itemStatus == .external {
            badges.append(.external)
        }
        if overlay.isMergeInfoOnly {
            badges.append(.mergeInfo)
        }
        return badges
    }

    private static func baseBadge(for status: FileStatus) -> FinderSyncBadge {
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
        case .locked:
            return 65
        case .switched:
            return 55
        case .nested:
            return 65
        case .shallow:
            return 50
        case .needsLock:
            return 40
        case .mergeInfo:
            return 75
        }
    }

    private static func menuActions(for status: FileStatus?) -> [FinderSyncMenuAction] {
        let itemStatus = status?.itemStatus ?? .normal
        let isConflicted = status?.isTreeConflict == true || itemStatus == .conflicted
        let isUnversioned = itemStatus == .unversioned
        let isIgnored = itemStatus == .ignored
        let isVersioned = !isUnversioned && !isIgnored
        let hasLocalChange = isConflicted
            || [.modified, .added, .deleted, .missing, .replaced].contains(itemStatus)
        let canCommit = hasLocalChange && !isConflicted
        let canDiff = isConflicted || [.modified, .added, .deleted, .replaced].contains(itemStatus)
        let canDelete = isVersioned && ![.deleted, .missing, .conflicted].contains(itemStatus)

        return [
            FinderSyncMenuAction(id: .update, title: "更新", isEnabled: true),
            FinderSyncMenuAction(id: .commit, title: "提交", isEnabled: canCommit),
            FinderSyncMenuAction(id: .log, title: "查看日志", isEnabled: isVersioned),
            FinderSyncMenuAction(id: .diff, title: "查看差异", isEnabled: canDiff),
            FinderSyncMenuAction(id: .revert, title: "还原", isEnabled: hasLocalChange),
            FinderSyncMenuAction(id: .add, title: "加入版本控制", isEnabled: isUnversioned),
            FinderSyncMenuAction(id: .delete, title: "SVN 删除", isEnabled: canDelete),
            FinderSyncMenuAction(id: .resolve, title: "解决冲突", isEnabled: isConflicted)
        ]
    }

    private static func normalize(_ path: String) -> String {
        path.split(separator: "/").joined(separator: "/")
    }
}
