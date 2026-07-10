import Foundation

/// 工作副本内 Rename 计划（同目录改名，对齐小乌龟 Rename 对话框）。
public struct RenamePlan: Equatable, Sendable {
    public let sourcePath: String
    public let destinationPath: String

    public init(sourcePath: String, destinationPath: String) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
    }
}

/// 纯函数：校验新文件名并拼出同目录目标路径。
public enum RenameValidationPolicy {
    public enum ValidationError: Error, Equatable, LocalizedError, Sendable {
        case emptyNewName
        case sameName
        case containsPathSeparator
        case invalidName
        case destinationExists(String)

        public var errorDescription: String? {
            switch self {
            case .emptyNewName:
                return "新名称不能为空"
            case .sameName:
                return "新名称与当前名称相同"
            case .containsPathSeparator:
                return "新名称不能包含路径分隔符（跨目录请用移动）"
            case .invalidName:
                return "新名称无效"
            case .destinationExists(let path):
                return "目标已存在：\(path)"
            }
        }
    }

    /// - Parameters:
    ///   - sourcePath: WC 相对路径
    ///   - newName: 用户输入的新文件名（不含目录）
    ///   - existingRelativePaths: 当前 WC 已有相对路径（用于冲突检测；不含 source 自身亦可）
    public static func resolve(
        sourcePath: String,
        newName: String,
        existingRelativePaths: Set<String> = []
    ) -> Result<RenamePlan, ValidationError> {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.emptyNewName)
        }
        if trimmed.contains("/") || trimmed.contains("\\") {
            return .failure(.containsPathSeparator)
        }
        if trimmed == "." || trimmed == ".." {
            return .failure(.invalidName)
        }

        let currentName = (sourcePath as NSString).lastPathComponent
        if trimmed == currentName {
            return .failure(.sameName)
        }

        let parent = (sourcePath as NSString).deletingLastPathComponent
        let destination: String
        if parent.isEmpty || parent == "." {
            destination = trimmed
        } else {
            destination = (parent as NSString).appendingPathComponent(trimmed)
        }

        // macOS 默认大小写不敏感：同目录已有不同文件的大小写变体视为冲突；
        // 仅改自身大小写（#46）仍放行，交给 svn。
        let collision = existingRelativePaths.first { path in
            path.compare(destination, options: [.caseInsensitive, .literal]) == .orderedSame
                && path.compare(sourcePath, options: [.caseInsensitive, .literal]) != .orderedSame
        }
        if let collision {
            return .failure(.destinationExists(collision))
        }

        return .success(RenamePlan(sourcePath: sourcePath, destinationPath: destination))
    }
}
