import Foundation

public struct FinderSyncContextMenuSettings: Codable, Equatable, Sendable {
    public static let defaultPromotedCommandIDs: [SvnCommandID] = [
        .update, .commit, .showLog, .diff, .revert, .resolved,
    ]

    public var promotedCommandIDs: [SvnCommandID]
    public var promoteLockForNeedsLock: Bool
    public var hideMenusForUnversionedItems: Bool
    public var excludedPaths: [String]

    public init(
        promotedCommandIDs: [SvnCommandID] = Self.defaultPromotedCommandIDs,
        promoteLockForNeedsLock: Bool = true,
        hideMenusForUnversionedItems: Bool = false,
        excludedPaths: [String] = []
    ) {
        self.promotedCommandIDs = Self.cleanedCommandIDs(promotedCommandIDs)
        self.promoteLockForNeedsLock = promoteLockForNeedsLock
        self.hideMenusForUnversionedItems = hideMenusForUnversionedItems
        self.excludedPaths = Self.cleanedPaths(excludedPaths)
    }

    public func excludes(path: String) -> Bool {
        guard let normalized = Self.normalizedAbsolutePath(path) else { return false }
        return excludedPaths.compactMap(Self.normalizedAbsolutePath).contains {
            Self.isSameOrDescendant(normalized, of: $0)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case promotedCommandIDs
        case promoteLockForNeedsLock
        case hideMenusForUnversionedItems
        case excludedPaths
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        promotedCommandIDs = Self.cleanedCommandIDs(
            try container.decodeIfPresent([SvnCommandID].self, forKey: .promotedCommandIDs)
                ?? Self.defaultPromotedCommandIDs
        )
        promoteLockForNeedsLock = try container.decodeIfPresent(
            Bool.self,
            forKey: .promoteLockForNeedsLock
        ) ?? true
        hideMenusForUnversionedItems = try container.decodeIfPresent(
            Bool.self,
            forKey: .hideMenusForUnversionedItems
        ) ?? false
        excludedPaths = Self.cleanedPaths(
            try container.decodeIfPresent([String].self, forKey: .excludedPaths) ?? []
        )
    }

    private static func cleanedCommandIDs(_ commandIDs: [SvnCommandID]) -> [SvnCommandID] {
        let allowed = Set(SvnCommandCatalog.dailyCFMCommandIDs)
        var seen: Set<SvnCommandID> = []
        return commandIDs.filter { allowed.contains($0) && seen.insert($0).inserted }
    }

    private static func cleanedPaths(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.compactMap { path in
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return nil }
            seen.insert(trimmed)
            return trimmed
        }
    }

    private static func normalizedAbsolutePath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        return (expanded as NSString).standardizingPath
    }

    private static func isSameOrDescendant(_ path: String, of parent: String) -> Bool {
        if path == parent { return true }
        if parent == "/" { return path.hasPrefix("/") }
        return path.hasPrefix(parent + "/")
    }
}
