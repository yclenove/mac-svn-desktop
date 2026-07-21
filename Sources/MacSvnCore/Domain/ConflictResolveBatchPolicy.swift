import Foundation

/// 批量 Resolved 结果：允许部分成功，避免「一失败全盘报错」掩盖已解决路径。
public struct ConflictBatchResolveOutcome: Equatable, Sendable {
    public let succeededPaths: [String]
    public let failedPaths: [String]
    public let errorSummaries: [String]

    public init(
        succeededPaths: [String] = [],
        failedPaths: [String] = [],
        errorSummaries: [String] = []
    ) {
        self.succeededPaths = succeededPaths
        self.failedPaths = failedPaths
        self.errorSummaries = errorSummaries
    }

    public var succeededCount: Int { succeededPaths.count }
    public var hasFailures: Bool { !failedPaths.isEmpty }
}

/// 批量「标记为已解决」（#12 Resolved）策略。
///
/// 文本/属性冲突可用 `svn resolve --accept working`；
/// 树冲突需专用 keepLocal/acceptRemote 流程，默认不进入批量 Resolved。
public enum ConflictResolveBatchPolicy: Sendable {
    public static func isEligibleForMarkResolved(_ conflict: ConflictInfo) -> Bool {
        switch conflict.kind {
        case .text, .property:
            return true
        case .tree, .unknown:
            return false
        }
    }

    /// CFM 行级判定：树冲突走专用面板；`conflicted` 文本/属性可批量 Resolved。
    public static func isEligibleForMarkResolved(itemStatus: ItemStatus, isTreeConflict: Bool) -> Bool {
        guard !isTreeConflict else { return false }
        return itemStatus == .conflicted
    }

    public static func pathsEligibleForMarkResolved(from conflicts: [ConflictInfo]) -> [String] {
        conflicts
            .filter(isEligibleForMarkResolved)
            .map(\.path)
    }

    /// 从勾选路径中筛出可批量 Resolved 的项（保持勾选顺序稳定：按 conflicts 顺序）。
    public static func filterCheckedPaths(
        checked: Set<String>,
        conflicts: [ConflictInfo]
    ) -> [String] {
        conflicts
            .filter { checked.contains($0.path) && isEligibleForMarkResolved($0) }
            .map(\.path)
    }
}
