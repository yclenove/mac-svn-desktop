import Foundation

/// Progress 对话框完成后的自动关闭档位（对齐 Tortoise Dialogs 3）。
public enum ProgressAutoCloseMode: String, Codable, CaseIterable, Equatable, Sendable {
    case manual
    case noMerges
    case noConflicts
    case noErrors

    public var displayName: String {
        switch self {
        case .manual: return "手动"
        case .noMerges: return "无合并增删"
        case .noConflicts: return "无冲突"
        case .noErrors: return "无错误"
        }
    }
}

public struct ProgressOperationOutcome: Equatable, Sendable {
    public let hasErrors: Bool
    public let hasConflicts: Bool
    public let hasMerges: Bool

    public init(hasErrors: Bool, hasConflicts: Bool, hasMerges: Bool) {
        self.hasErrors = hasErrors
        self.hasConflicts = hasConflicts
        self.hasMerges = hasMerges
    }

    public static let successful = ProgressOperationOutcome(
        hasErrors: false,
        hasConflicts: false,
        hasMerges: false
    )
    public static let conflicted = ProgressOperationOutcome(
        hasErrors: false,
        hasConflicts: true,
        hasMerges: false
    )
    public static let merged = ProgressOperationOutcome(
        hasErrors: false,
        hasConflicts: false,
        hasMerges: true
    )
    public static let failed = ProgressOperationOutcome(
        hasErrors: true,
        hasConflicts: false,
        hasMerges: false
    )
}

public enum ProgressAutoClosePolicy {
    public static func shouldClose(
        mode: ProgressAutoCloseMode,
        outcome: ProgressOperationOutcome,
        isLocalOperation: Bool
    ) -> Bool {
        switch mode {
        case .manual:
            return false
        case .noErrors:
            return !outcome.hasErrors
        case .noConflicts:
            return !outcome.hasErrors && !outcome.hasConflicts
        case .noMerges:
            return !outcome.hasErrors
                && !outcome.hasConflicts
                && (!outcome.hasMerges || isLocalOperation)
        }
    }
}
