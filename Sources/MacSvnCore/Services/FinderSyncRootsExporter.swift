import Foundation

/// Finder Sync 监视的工作副本根目录列表（主应用写入，扩展读取）。
public struct FinderSyncRootsFile: Codable, Equatable, Sendable {
    public var version: Int
    public var roots: [String]
    public var cacheMode: FinderSyncCacheMode
    public var overlaySettings: FinderSyncOverlaySettings

    public init(
        version: Int = 3,
        roots: [String] = [],
        cacheMode: FinderSyncCacheMode = .defaultCache,
        overlaySettings: FinderSyncOverlaySettings = FinderSyncOverlaySettings()
    ) {
        self.version = version
        self.roots = roots
        self.cacheMode = cacheMode
        self.overlaySettings = overlaySettings
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case roots
        case cacheMode
        case overlaySettings
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
    }
}

/// 导出/加载 Finder Sync 根目录清单。
public enum FinderSyncRootsExporter {
    public static let fileName = "finder-sync-roots.json"

    public static func fileURL(in supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent(fileName)
    }

    /// 仅导出有效工作副本路径，去重并排序，便于扩展稳定注册。
    public static func export(records: [WorkingCopyRecord], to fileURL: URL) throws {
        let existing = try? loadConfiguration(from: fileURL)
        try export(
            records: records,
            cacheMode: existing?.cacheMode ?? .defaultCache,
            overlaySettings: existing?.overlaySettings ?? FinderSyncOverlaySettings(),
            to: fileURL
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
            to: fileURL
        )
    }

    public static func export(
        records: [WorkingCopyRecord],
        cacheMode: FinderSyncCacheMode,
        overlaySettings: FinderSyncOverlaySettings,
        to fileURL: URL
    ) throws {
        let roots = Array(
            Set(records.filter(\.isValid).map(\.localPath))
        ).sorted()
        let payload = FinderSyncRootsFile(
            roots: roots,
            cacheMode: cacheMode,
            overlaySettings: overlaySettings
        )
        let data = try JSONEncoder().encode(payload)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
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
