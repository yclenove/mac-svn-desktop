import Foundation

/// Show Log「复制到剪贴板」（L17）：将修订摘要格式化为纯文本。
///
/// 对齐小乌龟常见摘要：修订 / 作者 / 日期 / 说明 / 变更路径列表。
public enum LogClipboardSummary: Sendable {
    public static func text(for entry: LogEntry, dateFormatter: DateFormatter? = nil) -> String {
        let formatter = dateFormatter ?? Self.defaultDateFormatter
        var lines: [String] = []
        lines.append("Revision: \(entry.revision.value)")
        lines.append("Author: \(entry.author.isEmpty ? "unknown" : entry.author)")
        if let date = entry.date {
            lines.append("Date: \(formatter.string(from: date))")
        } else {
            lines.append("Date: (unknown)")
        }
        lines.append("Message:")
        let message = entry.message.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(message.isEmpty ? "(no message)" : message)
        if !entry.changedPaths.isEmpty {
            lines.append("----")
            lines.append("Changed paths:")
            for change in entry.changedPaths {
                lines.append("   \(change.action.rawValue) \(change.path)")
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func text(for entries: [LogEntry], dateFormatter: DateFormatter? = nil) -> String {
        entries.map { text(for: $0, dateFormatter: dateFormatter) }.joined(separator: "\n\n")
    }

    private static let defaultDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()
}
