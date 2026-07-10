import Foundation

/// Show Log 客户端过滤（L18）：作者 / 说明 / 路径子串，大小写不敏感。
///
/// 统计与离线缓存属 T3；本策略只负责列表过滤匹配。
public enum LogFilterPolicy: Sendable {
    public static func matches(
        _ entry: LogEntry,
        authorQuery: String,
        messageQuery: String,
        pathQuery: String
    ) -> Bool {
        let author = authorQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = messageQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = pathQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if !author.isEmpty, !entry.author.localizedCaseInsensitiveContains(author) {
            return false
        }
        if !message.isEmpty, !entry.message.localizedCaseInsensitiveContains(message) {
            return false
        }
        if !path.isEmpty {
            let hit = entry.changedPaths.contains { $0.path.localizedCaseInsensitiveContains(path) }
            if !hit {
                return false
            }
        }
        return true
    }
}
