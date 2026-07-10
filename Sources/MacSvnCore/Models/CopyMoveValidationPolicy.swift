import Foundation

/// 工作副本内复制 / 移动（对齐小乌龟 Copy/Move 向导）。
public enum CopyMoveKind: String, CaseIterable, Equatable, Sendable {
    case copy
    case move

    public var displayName: String {
        switch self {
        case .copy: return "复制"
        case .move: return "移动"
        }
    }
}

public struct CopyMovePlan: Equatable, Sendable {
    public let kind: CopyMoveKind
    public let sourcePath: String
    public let destinationPath: String

    public init(kind: CopyMoveKind, sourcePath: String, destinationPath: String) {
        self.kind = kind
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
    }
}

/// 纯函数：校验目标相对路径并生成 Copy/Move 计划。
public enum CopyMoveValidationPolicy {
    public enum ValidationError: Error, Equatable, LocalizedError, Sendable {
        case emptyDestination
        case absoluteDestination
        case samePath
        case escapesWorkingCopy
        case destinationExists(String)

        public var errorDescription: String? {
            switch self {
            case .emptyDestination:
                return "目标路径不能为空"
            case .absoluteDestination:
                return "目标须为工作副本内相对路径"
            case .samePath:
                return "目标与源路径相同"
            case .escapesWorkingCopy:
                return "目标不能跳出工作副本（含 ..）"
            case .destinationExists(let path):
                return "目标已存在：\(path)"
            }
        }
    }

    public static func resolve(
        kind: CopyMoveKind,
        sourcePath: String,
        destinationPath: String,
        existingRelativePaths: Set<String> = []
    ) -> Result<CopyMovePlan, ValidationError> {
        let trimmedSource = sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            return .failure(.emptyDestination)
        }

        let rawDest = destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawDest.isEmpty else {
            return .failure(.emptyDestination)
        }
        if rawDest.hasPrefix("/") {
            return .failure(.absoluteDestination)
        }

        guard let normalized = normalizeRelativePath(rawDest) else {
            return .failure(.escapesWorkingCopy)
        }
        if normalized.isEmpty {
            return .failure(.emptyDestination)
        }

        if normalized.compare(trimmedSource, options: [.caseInsensitive, .literal]) == .orderedSame {
            return .failure(.samePath)
        }

        let collision = existingRelativePaths.first { path in
            path.compare(normalized, options: [.caseInsensitive, .literal]) == .orderedSame
                && path.compare(trimmedSource, options: [.caseInsensitive, .literal]) != .orderedSame
        }
        if let collision {
            return .failure(.destinationExists(collision))
        }

        return .success(CopyMovePlan(kind: kind, sourcePath: trimmedSource, destinationPath: normalized))
    }

    /// 去掉 `./`、折叠多余 `/`，拒绝 `..` 跳出 WC。
    public static func normalizeRelativePath(_ path: String) -> String? {
        var parts: [String] = []
        for raw in path.split(separator: "/", omittingEmptySubsequences: true) {
            let part = String(raw)
            if part == "." { continue }
            if part == ".." {
                if parts.isEmpty { return nil }
                parts.removeLast()
                continue
            }
            if part == "\\" || part.contains("\\") {
                // 反斜杠路径段视为非法相对路径
                return nil
            }
            parts.append(part)
        }
        return parts.joined(separator: "/")
    }
}
