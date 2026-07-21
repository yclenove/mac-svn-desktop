import Foundation

public struct FinderSyncMenuTargetState: Equatable, Sendable {
    public let path: String
    public let itemStatus: ItemStatus?
    public let hasNeedsLock: Bool
    public let isReadOnly: Bool
    public let isRepositoryLocked: Bool

    public init(
        path: String,
        itemStatus: ItemStatus?,
        hasNeedsLock: Bool = false,
        isReadOnly: Bool = false,
        isRepositoryLocked: Bool = false
    ) {
        self.path = path
        self.itemStatus = itemStatus
        self.hasNeedsLock = hasNeedsLock
        self.isReadOnly = isReadOnly
        self.isRepositoryLocked = isRepositoryLocked
    }
}

public struct FinderSyncContextMenuPlan: Equatable, Sendable {
    public let isHidden: Bool
    public let promotedCommandIDs: [SvnCommandID]
    public let submenuCommandIDs: [SvnCommandID]

    public init(
        isHidden: Bool,
        promotedCommandIDs: [SvnCommandID],
        submenuCommandIDs: [SvnCommandID]
    ) {
        self.isHidden = isHidden
        self.promotedCommandIDs = promotedCommandIDs
        self.submenuCommandIDs = submenuCommandIDs
    }
}

public struct FinderSyncContextMenuBuilder: Sendable {
    public init() {}

    public func plan(
        targets: [FinderSyncMenuTargetState],
        settings: FinderSyncContextMenuSettings
    ) -> FinderSyncContextMenuPlan {
        let excluded = targets.contains { settings.excludes(path: $0.path) }
        let allUnversioned = !targets.isEmpty && targets.allSatisfy {
            guard let status = $0.itemStatus else { return false }
            return status == .unversioned || status == .ignored
        }
        if excluded || (settings.hideMenusForUnversionedItems && allUnversioned) {
            return FinderSyncContextMenuPlan(
                isHidden: true,
                promotedCommandIDs: [],
                submenuCommandIDs: []
            )
        }

        var promoted = settings.promotedCommandIDs
        let shouldPromoteLock = settings.promoteLockForNeedsLock && targets.contains {
            $0.hasNeedsLock && $0.isReadOnly && !$0.isRepositoryLocked
        }
        if shouldPromoteLock, !promoted.contains(.getLock) {
            promoted.append(.getLock)
        }

        let promotedSet = Set(promoted)
        let submenu = SvnCommandCatalog.dailyCFMCommandIDs.filter { !promotedSet.contains($0) }
        return FinderSyncContextMenuPlan(
            isHidden: false,
            promotedCommandIDs: promoted,
            submenuCommandIDs: submenu
        )
    }
}
