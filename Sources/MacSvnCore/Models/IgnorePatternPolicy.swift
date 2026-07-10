import Foundation

/// 忽略模式种类（对齐小乌龟「按文件名 / 按扩展名」）。
public enum IgnorePatternKind: String, CaseIterable, Equatable, Sendable {
    /// 精确 basename，如 `cache.tmp`
    case exactFilename
    /// 扩展名通配，如 `*.tmp`（无扩展名时不可用）
    case extensionWildcard

    public var displayName: String {
        switch self {
        case .exactFilename: return "按文件名"
        case .extensionWildcard: return "按扩展名（*.ext）"
        }
    }
}

/// 写入某一父目录 `svn:ignore` 的计划。
public struct IgnorePropertyPlan: Equatable, Sendable {
    /// 属性所在目录（WC 相对路径；根为 `"."`）
    public let target: String
    /// 要追加的模式（已去重）
    public let patterns: [String]

    public init(target: String, patterns: [String]) {
        self.target = target
        self.patterns = patterns
    }
}

/// 纯函数：从选中路径生成 ignore 模式与合并后的属性值。
public enum IgnorePatternPolicy {
    /// 单个路径对应的 ignore 模式；通配在无扩展名时返回 `nil`。
    public static func pattern(forRelativePath path: String, kind: IgnorePatternKind) -> String? {
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else { return nil }

        switch kind {
        case .exactFilename:
            return name
        case .extensionWildcard:
            // 隐藏文件 `.env`、无扩展名 `Makefile` 不生成通配
            guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
                return nil
            }
            let ext = String(name[name.index(after: dot)...])
            guard !ext.isEmpty else { return nil }
            return "*.\(ext)"
        }
    }

    /// `svn:ignore` 所在目录（相对 WC）。
    public static func parentTarget(forRelativePath path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        if parent.isEmpty || parent == "." {
            return "."
        }
        return parent
    }

    /// 按父目录聚合要写入的模式（同目录同模式去重，保持稳定顺序）。
    public static func plans(relativePaths: [String], kind: IgnorePatternKind) -> [IgnorePropertyPlan] {
        var orderedTargets: [String] = []
        var patternsByTarget: [String: [String]] = [:]
        var seenByTarget: [String: Set<String>] = [:]

        for path in relativePaths.sorted() {
            guard let pattern = pattern(forRelativePath: path, kind: kind) else { continue }
            let target = parentTarget(forRelativePath: path)
            if patternsByTarget[target] == nil {
                orderedTargets.append(target)
                patternsByTarget[target] = []
                seenByTarget[target] = []
            }
            if seenByTarget[target]?.contains(pattern) != true {
                patternsByTarget[target]?.append(pattern)
                seenByTarget[target]?.insert(pattern)
            }
        }

        return orderedTargets.compactMap { target in
            guard let patterns = patternsByTarget[target], !patterns.isEmpty else { return nil }
            return IgnorePropertyPlan(target: target, patterns: patterns)
        }
    }

    /// 将新模式追加到已有 `svn:ignore` 文本（去重，末尾换行）。
    public static func mergeIgnoreProperty(existing: String?, patterns: [String]) -> String {
        var lines = (existing ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if lines.last == "" {
            lines.removeLast()
        }
        let existingSet = Set(lines.filter { !$0.isEmpty })
        for pattern in patterns where !existingSet.contains(pattern) {
            lines.append(pattern)
        }
        if lines.isEmpty {
            return ""
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
