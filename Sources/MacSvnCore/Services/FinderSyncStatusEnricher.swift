import Foundation

public struct FinderSyncPathMetadata: Equatable, Sendable {
    public let path: String
    public let isReadOnly: Bool
    public let depth: SvnDepth?
    public let isNestedWorkingCopy: Bool

    public init(
        path: String,
        isReadOnly: Bool = false,
        depth: SvnDepth? = nil,
        isNestedWorkingCopy: Bool = false
    ) {
        self.path = path
        self.isReadOnly = isReadOnly
        self.depth = depth
        self.isNestedWorkingCopy = isNestedWorkingCopy
    }
}

public enum FinderSyncStatusEnricher: Sendable {
    public static func enrich(
        statuses: [FileStatus],
        currentProperties: [SvnProperty],
        baseProperties: [SvnProperty]?,
        pathMetadata: [FinderSyncPathMetadata]
    ) -> [FileStatus] {
        let currentByPath = propertySnapshots(currentProperties)
        let baseByPath = baseProperties.map(propertySnapshots)
        let metadataByPath = Dictionary(
            pathMetadata.map { (normalize($0.path), $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        return statuses.map { status in
            let path = normalize(status.path)
            let current = currentByPath[path] ?? [:]
            let base = baseByPath?[path] ?? [:]
            let metadata = metadataByPath[path]
            let changedNames = baseByPath == nil ? [] : changedPropertyNames(current: current, base: base)
            let mergeInfoOnly = status.overlay.propertyStatus == .modified
                && changedNames == Set(["svn:mergeinfo"])

            let overlay = FileStatusOverlayMetadata(
                propertyStatus: status.overlay.propertyStatus,
                isWorkingCopyLocked: status.overlay.isWorkingCopyLocked,
                isRepositoryLocked: status.overlay.isRepositoryLocked,
                isSwitched: status.overlay.isSwitched,
                isFileExternal: status.overlay.isFileExternal,
                hasNeedsLock: status.overlay.hasNeedsLock || current["svn:needs-lock"] != nil,
                isReadOnly: status.overlay.isReadOnly || (metadata?.isReadOnly ?? false),
                depth: metadata?.depth ?? status.overlay.depth,
                isNestedWorkingCopy: status.overlay.isNestedWorkingCopy
                    || (metadata?.isNestedWorkingCopy ?? false),
                isMergeInfoOnly: status.overlay.isMergeInfoOnly || mergeInfoOnly
            )
            return FileStatus(
                path: status.path,
                itemStatus: status.itemStatus,
                revision: status.revision,
                isTreeConflict: status.isTreeConflict,
                remoteItemStatus: status.remoteItemStatus,
                changelist: status.changelist,
                overlay: overlay
            )
        }
    }

    private static func propertySnapshots(_ properties: [SvnProperty]) -> [String: [String: String]] {
        var snapshots: [String: [String: String]] = [:]
        for property in properties {
            snapshots[normalize(property.target), default: [:]][property.name] = property.value
        }
        return snapshots
    }

    private static func changedPropertyNames(
        current: [String: String],
        base: [String: String]
    ) -> Set<String> {
        Set(current.keys).union(base.keys).filter { current[$0] != base[$0] }
    }

    private static func normalize(_ path: String) -> String {
        let components = path.split(separator: "/")
        return components.isEmpty ? "." : components.joined(separator: "/")
    }
}
