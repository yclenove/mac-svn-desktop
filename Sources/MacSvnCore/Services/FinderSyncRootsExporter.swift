import Foundation

/// Finder Sync 监视的工作副本根目录列表（主应用写入，扩展读取）。
public struct FinderSyncRootsFile: Codable, Equatable, Sendable {
    public var version: Int
    public var roots: [String]

    public init(version: Int = 1, roots: [String] = []) {
        self.version = version
        self.roots = roots
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
        let roots = Array(
            Set(records.filter(\.isValid).map(\.localPath))
        ).sorted()
        let payload = FinderSyncRootsFile(roots: roots)
        let data = try JSONEncoder().encode(payload)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
    }

    public static func load(from fileURL: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        let file = try JSONDecoder().decode(FinderSyncRootsFile.self, from: data)
        return file.roots.filter { !$0.isEmpty }
    }
}
