import Foundation

/// 锁定相关操作意图（对齐 Tortoise #19–#21）。
public enum LockActionIntent: String, Equatable, Sendable {
    /// 获取锁：`svn lock [-m] [--force]`
    case getLock
    /// 释放锁：`svn unlock`（本 WC 持有）
    case releaseLock
    /// 打断锁：`svn unlock --force`（高危）
    case breakLock
}

/// 锁定操作策略：路径筛选与确认门控语义。
public enum LockActionPolicy: Sendable {
    /// 释放锁：优先本 WC 持有的锁。
    /// - 已有锁列表时：仅返回本 WC 持有项（可为空，避免误 unlock 他人锁）。
    /// - 尚无锁列表时（CFM 直达）：保留选中路径交由 svn 判定。
    public static func pathsEligibleForRelease(
        selected: [String],
        locks: [SvnLock]
    ) -> [String] {
        let selectedSet = Set(selected)
        let owned = locks
            .filter { selectedSet.contains($0.target) && $0.isOwnedByWorkingCopy }
            .map(\.target)
        if !locks.isEmpty {
            return owned.sorted()
        }
        return selected.filter { !$0.isEmpty }.sorted()
    }

    /// 打断锁：仓库侧有锁的路径。
    /// - 已有锁列表时：仅返回仓库锁定项（可为空）。
    /// - 尚无锁列表时：用选中路径。
    public static func pathsEligibleForBreak(
        selected: [String],
        locks: [SvnLock]
    ) -> [String] {
        let selectedSet = Set(selected)
        let locked = locks
            .filter { selectedSet.contains($0.target) && $0.isRepositoryLocked }
            .map(\.target)
        if !locks.isEmpty {
            return locked.sorted()
        }
        return selected.filter { !$0.isEmpty }.sorted()
    }

    /// 获取锁 / 夺锁：任意非空选中路径。
    public static func pathsEligibleForGetLock(selected: [String]) -> [String] {
        selected.filter { !$0.isEmpty }.sorted()
    }

    /// 打断锁与夺锁均需显式确认。
    public static func requiresConfirmation(_ intent: LockActionIntent, steal: Bool = false) -> Bool {
        switch intent {
        case .breakLock:
            return true
        case .getLock:
            return steal
        case .releaseLock:
            return false
        }
    }
}
