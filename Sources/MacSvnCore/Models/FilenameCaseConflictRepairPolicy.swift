import Foundation

/// 工作副本大小写冲突修复计划。
public struct FilenameCaseConflictRepairPlan: Equatable, Sendable {
    public let sourcePath: String
    public let destinationPath: String

    public init(sourcePath: String, destinationPath: String) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
    }
}

/// 校验只能通过临时路径中转完成的 case-only rename。
public enum FilenameCaseConflictRepairPolicy {
    public enum ValidationError: Error, Equatable, LocalizedError, Sendable {
        case emptyNewName
        case sameName
        case containsPathSeparator
        case invalidName
        case notCaseOnlyRename
        case destinationExists(String)

        public var errorDescription: String? {
            switch self {
            case .emptyNewName:
                return "新名称不能为空"
            case .sameName:
                return "新名称与当前名称相同"
            case .containsPathSeparator:
                return "新名称不能包含路径分隔符"
            case .invalidName:
                return "新名称无效"
            case .notCaseOnlyRename:
                return "目标必须与当前名称仅大小写不同"
            case .destinationExists(let path):
                return "目标已存在：\(path)"
            }
        }
    }

    public static func resolve(
        sourcePath: String,
        newName: String,
        existingRelativePaths: Set<String> = []
    ) -> Result<FilenameCaseConflictRepairPlan, ValidationError> {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyNewName) }
        guard !trimmed.contains("/") && !trimmed.contains("\\") else {
            return .failure(.containsPathSeparator)
        }
        guard trimmed != ".", trimmed != ".." else { return .failure(.invalidName) }

        let sourceName = (sourcePath as NSString).lastPathComponent
        guard trimmed != sourceName else { return .failure(.sameName) }
        guard sourceName.compare(trimmed, options: [.caseInsensitive, .literal]) == .orderedSame else {
            return .failure(.notCaseOnlyRename)
        }

        let parent = (sourcePath as NSString).deletingLastPathComponent
        let destination = parent.isEmpty || parent == "."
            ? trimmed
            : (parent as NSString).appendingPathComponent(trimmed)

        let collision = existingRelativePaths.first { path in
            path != sourcePath
                && path.compare(destination, options: [.caseInsensitive, .literal]) == .orderedSame
        }
        if let collision { return .failure(.destinationExists(collision)) }

        return .success(FilenameCaseConflictRepairPlan(
            sourcePath: sourcePath,
            destinationPath: destination
        ))
    }
}
