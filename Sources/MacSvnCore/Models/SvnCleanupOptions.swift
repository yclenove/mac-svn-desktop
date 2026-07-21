import Foundation

/// `svn cleanup` 可选参数（对齐小乌龟 Cleanup 对话框常用项；不含删除未版本——见 #16）。
public struct SvnCleanupOptions: Equatable, Sendable {
    /// `--break-locks`：强制解除卡死的 WC 锁
    public var breakLocks: Bool
    /// `--vacuum-pristines`：清理未引用的 pristine（svn ≥ 1.10）
    public var vacuumPristines: Bool
    /// `--include-externals`：同时清理外部项
    public var includeExternals: Bool

    public init(
        breakLocks: Bool = false,
        vacuumPristines: Bool = false,
        includeExternals: Bool = false
    ) {
        self.breakLocks = breakLocks
        self.vacuumPristines = vacuumPristines
        self.includeExternals = includeExternals
    }

    public static let `default` = SvnCleanupOptions()
}

/// Add 对话框：从 status 提取可添加（未版本）路径，供勾选列表。
public enum AddCandidatesPolicy {
    public static func candidates(from statuses: [FileStatus]) -> [FileStatus] {
        statuses.filter { $0.itemStatus == .unversioned }
    }

    /// 默认勾选：若已有选中则取交集；否则全选未版本项。
    public static func defaultSelectedPaths(
        from statuses: [FileStatus],
        preselected: Set<String> = []
    ) -> Set<String> {
        let unversioned = Set(candidates(from: statuses).map(\.path))
        let intersection = unversioned.intersection(preselected)
        return intersection.isEmpty ? unversioned : intersection
    }
}
