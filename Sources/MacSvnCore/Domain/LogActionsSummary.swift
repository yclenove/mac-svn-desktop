import Foundation

/// 从 verbose 日志的 `changedPaths` 汇总 Tortoise「Actions」列符号（L19）。
///
/// 顺序固定为 M / A / D / R，与小乌龟常见展示一致；无路径明细时返回空串。
public enum LogActionsSummary: Sendable {
    public static func symbols(for changedPaths: [ChangedPath]) -> String {
        guard !changedPaths.isEmpty else { return "" }
        var seen = Set<ChangedPathAction>()
        for path in changedPaths {
            switch path.action {
            case .modified, .added, .deleted, .replaced:
                seen.insert(path.action)
            case .unknown:
                continue
            }
        }
        var result = ""
        if seen.contains(.modified) { result += "M" }
        if seen.contains(.added) { result += "A" }
        if seen.contains(.deleted) { result += "D" }
        if seen.contains(.replaced) { result += "R" }
        return result
    }
}
