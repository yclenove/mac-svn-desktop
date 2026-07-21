import Foundation

/// CFM「修复移动 / 修复复制」配对种类（对齐 TortoiseSVN Repair Move/Copy）。
public enum RepairMoveCopyKind: Equatable, Sendable {
    /// missing + unversioned → `svn move --force`
    case move
    /// 已版本化 + unversioned → `svn copy --force`
    case copy
}

/// 校验通过后的源/宿路径（相对工作副本）。
public struct RepairMoveCopyPair: Equatable, Sendable {
    public let kind: RepairMoveCopyKind
    public let sourcePath: String
    public let destinationPath: String

    public init(kind: RepairMoveCopyKind, sourcePath: String, destinationPath: String) {
        self.kind = kind
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
    }
}

/// 纯函数：从 CFM 多选与 status 列表解析 Repair 配对。
///
/// 约束（对齐小乌龟）：
/// - 必须恰好选中 2 项；
/// - Repair Move：一项 `missing`，一项 `unversioned`；
/// - Repair Copy：一项可作为 copy 源的已版本化状态，一项 `unversioned`。
public enum RepairMoveCopyPairing {
    public enum ValidationError: Error, Equatable, LocalizedError, Sendable {
        case needExactlyTwoSelections(count: Int)
        case statusMissing(path: String)
        case invalidMovePair
        case invalidCopyPair

        public var errorDescription: String? {
            switch self {
            case .needExactlyTwoSelections(let count):
                return "修复移动/复制需恰好选中 2 项（当前 \(count) 项）"
            case .statusMissing(let path):
                return "选中路径无 status 信息：\(path)"
            case .invalidMovePair:
                return "修复移动需一项「丢失」与一项「未版本」"
            case .invalidCopyPair:
                return "修复复制需一项已版本化文件与一项「未版本」"
            }
        }
    }

    /// 解析配对；失败返回可读错误（供 UI banner / ViewModel state）。
    public static func resolve(
        kind: RepairMoveCopyKind,
        selectedPaths: Set<String>,
        statuses: [FileStatus]
    ) -> Result<RepairMoveCopyPair, ValidationError> {
        guard selectedPaths.count == 2 else {
            return .failure(.needExactlyTwoSelections(count: selectedPaths.count))
        }

        let byPath = Dictionary(uniqueKeysWithValues: statuses.map { ($0.path, $0) })
        var resolved: [FileStatus] = []
        for path in selectedPaths {
            guard let status = byPath[path] else {
                return .failure(.statusMissing(path: path))
            }
            resolved.append(status)
        }

        switch kind {
        case .move:
            return resolveMove(resolved)
        case .copy:
            return resolveCopy(resolved)
        }
    }

    /// 当前选中是否可启用对应菜单（不抛错，仅布尔）。
    public static func canRepair(
        kind: RepairMoveCopyKind,
        selectedPaths: Set<String>,
        statuses: [FileStatus]
    ) -> Bool {
        if case .success = resolve(kind: kind, selectedPaths: selectedPaths, statuses: statuses) {
            return true
        }
        return false
    }

    private static func resolveMove(_ selected: [FileStatus]) -> Result<RepairMoveCopyPair, ValidationError> {
        let missing = selected.filter { $0.itemStatus == .missing }
        let unversioned = selected.filter { $0.itemStatus == .unversioned }
        guard missing.count == 1, unversioned.count == 1 else {
            return .failure(.invalidMovePair)
        }
        return .success(RepairMoveCopyPair(
            kind: .move,
            sourcePath: missing[0].path,
            destinationPath: unversioned[0].path
        ))
    }

    private static func resolveCopy(_ selected: [FileStatus]) -> Result<RepairMoveCopyPair, ValidationError> {
        let sources = selected.filter { isCopySource($0.itemStatus) }
        let unversioned = selected.filter { $0.itemStatus == .unversioned }
        guard sources.count == 1, unversioned.count == 1 else {
            return .failure(.invalidCopyPair)
        }
        return .success(RepairMoveCopyPair(
            kind: .copy,
            sourcePath: sources[0].path,
            destinationPath: unversioned[0].path
        ))
    }

    /// 可作为 Repair Copy 源：工作副本中仍存在的已版本化项。
    private static func isCopySource(_ status: ItemStatus) -> Bool {
        switch status {
        case .normal, .modified, .replaced, .added:
            return true
        case .unversioned, .missing, .deleted, .conflicted, .ignored, .external,
             .incomplete, .obstructed, .none:
            return false
        }
    }
}
