import Foundation

/// Finder Sync 监视的工作副本根目录列表（主应用写入，扩展读取）。
public struct FinderSyncRootsFile: Codable, Equatable, Sendable {
    public var version: Int
    public var roots: [String]
    public var cacheMode: FinderSyncCacheMode
    public var overlaySettings: FinderSyncOverlaySettings
    public var contextMenuSettings: FinderSyncContextMenuSettings

    public init(
        version: Int = 4,
        roots: [String] = [],
        cacheMode: FinderSyncCacheMode = .defaultCache,
        overlaySettings: FinderSyncOverlaySettings = FinderSyncOverlaySettings(),
        contextMenuSettings: FinderSyncContextMenuSettings = FinderSyncContextMenuSettings()
    ) {
        self.version = version
        self.roots = roots
        self.cacheMode = cacheMode
        self.overlaySettings = overlaySettings
        self.contextMenuSettings = contextMenuSettings
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case roots
        case cacheMode
        case overlaySettings
        case contextMenuSettings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        roots = try container.decodeIfPresent([String].self, forKey: .roots) ?? []
        cacheMode = try container.decodeIfPresent(FinderSyncCacheMode.self, forKey: .cacheMode)
            ?? .defaultCache
        overlaySettings = try container.decodeIfPresent(
            FinderSyncOverlaySettings.self,
            forKey: .overlaySettings
        ) ?? FinderSyncOverlaySettings()
        contextMenuSettings = try container.decodeIfPresent(
            FinderSyncContextMenuSettings.self,
            forKey: .contextMenuSettings
        ) ?? FinderSyncContextMenuSettings()
    }
}

/// 导出/加载 Finder Sync 根目录清单。
public enum FinderSyncRootsExporter {
    public static let fileName = "finder-sync-roots.json"

    public static func extensionContainerSupportDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(ProductBranding.finderSyncBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
            .appendingPathComponent(ProductBranding.supportDirectoryName, isDirectory: true)
    }

    public static func fileURL(in supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent(fileName)
    }

    /// 仅导出有效工作副本路径，去重并排序，便于扩展稳定注册。
    public static func export(records: [WorkingCopyRecord], to fileURL: URL) throws {
        try export(records: records, to: [fileURL])
    }

    public static func export(records: [WorkingCopyRecord], to fileURLs: [URL]) throws {
        guard let primaryURL = fileURLs.first else { return }
        let existing = try? loadConfiguration(from: primaryURL)
        try export(
            records: records,
            cacheMode: existing?.cacheMode ?? .defaultCache,
            overlaySettings: existing?.overlaySettings ?? FinderSyncOverlaySettings(),
            contextMenuSettings: existing?.contextMenuSettings ?? FinderSyncContextMenuSettings(),
            to: fileURLs
        )
    }

    public static func export(
        records: [WorkingCopyRecord],
        cacheMode: FinderSyncCacheMode,
        to fileURL: URL
    ) throws {
        let existingOverlaySettings = (try? loadConfiguration(from: fileURL).overlaySettings)
            ?? FinderSyncOverlaySettings()
        try export(
            records: records,
            cacheMode: cacheMode,
            overlaySettings: existingOverlaySettings,
            contextMenuSettings: (try? loadConfiguration(from: fileURL).contextMenuSettings)
                ?? FinderSyncContextMenuSettings(),
            to: fileURL
        )
    }

    public static func export(
        records: [WorkingCopyRecord],
        cacheMode: FinderSyncCacheMode,
        overlaySettings: FinderSyncOverlaySettings,
        to fileURL: URL
    ) throws {
        let existingContextMenuSettings = (try? loadConfiguration(from: fileURL).contextMenuSettings)
            ?? FinderSyncContextMenuSettings()
        try export(
            records: records,
            cacheMode: cacheMode,
            overlaySettings: overlaySettings,
            contextMenuSettings: existingContextMenuSettings,
            to: fileURL
        )
    }

    public static func export(
        records: [WorkingCopyRecord],
        cacheMode: FinderSyncCacheMode,
        overlaySettings: FinderSyncOverlaySettings,
        contextMenuSettings: FinderSyncContextMenuSettings,
        to fileURL: URL
    ) throws {
        try export(
            records: records,
            cacheMode: cacheMode,
            overlaySettings: overlaySettings,
            contextMenuSettings: contextMenuSettings,
            to: [fileURL]
        )
    }

    public static func export(
        records: [WorkingCopyRecord],
        cacheMode: FinderSyncCacheMode,
        overlaySettings: FinderSyncOverlaySettings,
        contextMenuSettings: FinderSyncContextMenuSettings,
        to fileURLs: [URL]
    ) throws {
        let roots = Array(
            Set(records.filter(\.isValid).map(\.localPath))
        ).sorted()
        let payload = FinderSyncRootsFile(
            roots: roots,
            cacheMode: cacheMode,
            overlaySettings: overlaySettings,
            contextMenuSettings: contextMenuSettings
        )
        let data = try JSONEncoder().encode(payload)
        var writtenPaths = Set<String>()
        for fileURL in fileURLs {
            let normalizedURL = fileURL.standardizedFileURL
            guard writtenPaths.insert(normalizedURL.path).inserted else { continue }
            try FileManager.default.createDirectory(
                at: normalizedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: normalizedURL, options: [.atomic])
        }
    }

    public static func load(from fileURL: URL) throws -> [String] {
        try loadConfiguration(from: fileURL).roots.filter { !$0.isEmpty }
    }

    public static func loadConfiguration(from fileURL: URL) throws -> FinderSyncRootsFile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return FinderSyncRootsFile()
        }
        let data = try Data(contentsOf: fileURL)
        var file = try JSONDecoder().decode(FinderSyncRootsFile.self, from: data)
        file.roots = file.roots.filter { !$0.isEmpty }
        return file
    }
}
