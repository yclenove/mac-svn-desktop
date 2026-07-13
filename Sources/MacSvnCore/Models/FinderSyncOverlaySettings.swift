import Foundation

public struct FinderSyncOverlaySettings: Codable, Equatable, Sendable {
    public var includedPaths: [String]
    public var excludedPaths: [String]
    public var enabledBadges: Set<FinderSyncBadge>

    public init(
        includedPaths: [String] = [],
        excludedPaths: [String] = [],
        enabledBadges: Set<FinderSyncBadge> = Set(FinderSyncBadge.allCases)
    ) {
        self.includedPaths = Self.cleanedPaths(includedPaths)
        self.excludedPaths = Self.cleanedPaths(excludedPaths)
        self.enabledBadges = enabledBadges
    }

    public func allows(path: String) -> Bool {
        guard let normalized = Self.normalizedAbsolutePath(path) else { return false }
        let includes = includedPaths.compactMap(Self.normalizedAbsolutePath)
        let excludes = excludedPaths.compactMap(Self.normalizedAbsolutePath)
        let isIncluded = includedPaths.isEmpty || includes.contains {
            Self.isSameOrDescendant(normalized, of: $0)
        }
        let isExcluded = excludes.contains {
            Self.isSameOrDescendant(normalized, of: $0)
        }
        return isIncluded && !isExcluded
    }

    public func monitoredDirectories(for roots: [String]) -> [String] {
        let normalizedRoots = roots.compactMap(Self.normalizedAbsolutePath)
        let includes = includedPaths.compactMap(Self.normalizedAbsolutePath)
        let candidates: [String]

        if includedPaths.isEmpty {
            candidates = normalizedRoots
        } else {
            candidates = normalizedRoots.flatMap { root in
                includes.compactMap { includedPath in
                    if Self.isSameOrDescendant(includedPath, of: root) {
                        return includedPath
                    }
                    if Self.isSameOrDescendant(root, of: includedPath) {
                        return root
                    }
                    return nil
                }
            }
        }

        return Array(Set(candidates.filter(allows(path:)))).sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case includedPaths
        case excludedPaths
        case enabledBadges
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        includedPaths = Self.cleanedPaths(
            try container.decodeIfPresent([String].self, forKey: .includedPaths) ?? []
        )
        excludedPaths = Self.cleanedPaths(
            try container.decodeIfPresent([String].self, forKey: .excludedPaths) ?? []
        )
        let decodedBadges = try container.decodeIfPresent([FinderSyncBadge].self, forKey: .enabledBadges)
        enabledBadges = decodedBadges.map(Set.init) ?? Set(FinderSyncBadge.allCases)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(includedPaths, forKey: .includedPaths)
        try container.encode(excludedPaths, forKey: .excludedPaths)
        let orderedBadges = FinderSyncBadge.allCases.filter(enabledBadges.contains)
        try container.encode(orderedBadges, forKey: .enabledBadges)
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
