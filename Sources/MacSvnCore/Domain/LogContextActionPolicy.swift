import Foundation

/// Show Log 变更路径 → 工作副本相对目标（供 Diff / Blame / cat）。
public enum LogChangedPathPolicy: Sendable {
    /// 将 `svn log -v` 的仓库风格路径解析为相对当前 WC URL 的目标。
    ///
    /// 例：WC URL `…/trunk`，changedPath `/trunk/Sources/a.swift` → `Sources/a.swift`。
    public static func workingCopyRelativePath(
        changedPath: String,
        workingCopyURL: String
    ) -> String {
        let pathComponents = changedPath
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !pathComponents.isEmpty else { return "" }

        guard let url = URL(string: workingCopyURL) else {
            return pathComponents.joined(separator: "/")
        }

        let urlComponents = url.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        for drop in 0..<urlComponents.count {
            let suffix = Array(urlComponents.dropFirst(drop))
            if pathComponents.starts(with: suffix) {
                return pathComponents.dropFirst(suffix.count).joined(separator: "/")
            }
        }

        return pathComponents.joined(separator: "/")
    }

    /// 构造 peg URL：`url@rev`（L09 / L14）。
    public static func pegURL(workingCopyURL: String, revision: Revision) -> String {
        let base = workingCopyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(base)@\(revision.value)"
    }
}

/// 日志右键动作意图（L01–L14；L03/L13 属 T3，本策略不产出）。
public enum LogContextActionIntent: Equatable, Sendable {
    /// L01：修订 vs 工作副本（`svn diff -r REV`）
    case compareWithWorkingCopy(path: String, revision: Revision)
    /// L02：与上一修订比（`PREV:REV`）
    case compareWithPrevious(path: String, revision: Revision)
    /// L04：统一 Diff 文本（默认 PREV:REV）
    case showUnifiedDiff(path: String, revision: Revision)
    /// L05：另存该修订内容
    case saveRevision(path: String, revision: Revision)
    /// L06：用系统默认应用打开该修订内容
    case openRevision(path: String, revision: Revision)
    /// L07：Blame 该路径
    case blame(path: String, revision: Revision)
    /// L08：在仓库浏览器打开 URL@rev
    case browseRepository(path: String, revision: Revision, repositoryURL: String)
    /// L09：从修订创建分支/标签（`svn copy url@rev dest`）
    case createBranchTag(sourcePegURL: String, revision: Revision)
    /// L10：更新项到修订
    case updateToRevision(path: String, revision: Revision)
    /// L11：还原到此修订（`merge -r HEAD:REV`）
    case revertToRevision(path: String, revision: Revision)
    /// L12：撤销此修订的更改（`merge -r REV:REV-1`）
    case revertChangesFromRevision(path: String, revision: Revision)
    /// L14：从日志检出/导出
    case checkoutOrExport(sourcePegURL: String, revision: Revision)
    /// L13：将日志选中的单个修订合并到当前工作副本
    case mergeRevisionTo(sourceURL: String, revision: Revision)
}

/// 从 Catalog ID + 上下文解析可执行意图。
public enum LogContextActionPolicy: Sendable {
    /// T2.3 文件级动作（L01–L08，不含 L03）。
    public static let t2FileActionIDs: [SvnCommandID] = [
        .logCompareWithWorkingCopy,
        .logCompareWithPrevious,
        .logShowUnifiedDiff,
        .logSaveRevisionTo,
        .logOpen,
        .logBlame,
        .logBrowseRepository,
    ]

    /// T2.4 修订级动作（L09–L12、L14）。
    public static let t2RevisionActionIDs: [SvnCommandID] = [
        .logCreateBranchTagFromRevision,
        .logUpdateItemToRevision,
        .logRevertToThisRevision,
        .logRevertChangesFromThisRevision,
        .logCheckoutOrExport,
    ]

    /// T2.5 剪贴板（L17）。
    public static let t2ClipboardActionIDs: [SvnCommandID] = [
        .logCopyToClipboard,
    ]

    /// T3：从日志选择单个修订合并到当前工作副本。
    public static let t3RevisionActionIDs: [SvnCommandID] = [
        .logMergeRevisionTo,
    ]

    /// 兼容旧名。
    public static var t2ActionIDs: [SvnCommandID] { t2FileActionIDs }

    /// L12：单修订反向合并范围 `N:(N-1)`。
    public static func reverseSingleRevisionRange(_ revision: Revision) -> RevisionRange? {
        guard revision.value > 0 else { return nil }
        return RevisionRange(start: revision, end: Revision(revision.value - 1))
    }

    /// L11：从仓库 HEAD 反向合并到目标修订（HEAD 必须严格大于目标）。
    public static func revertToRevisionRange(head: Revision, target: Revision) -> RevisionRange? {
        guard head.value > target.value else { return nil }
        return RevisionRange(start: head, end: target)
    }

    /// 从 `url@rev` peg 解析裸 URL；仅剥离**最后一个** `@数字`，避免误伤 `user@host`。
    public static func stripPegRevision(from pegURL: String) -> String {
        guard let at = pegURL.lastIndex(of: "@") else { return pegURL }
        let suffix = pegURL[pegURL.index(after: at)...]
        if !suffix.isEmpty, suffix.allSatisfy(\.isNumber) {
            return String(pegURL[..<at])
        }
        return pegURL
    }

    public static func intent(
        command: SvnCommandID,
        changedPath: String,
        revision: Revision,
        workingCopyURL: String
    ) -> LogContextActionIntent? {
        switch command {
        case .logMergeRevisionTo:
            return .mergeRevisionTo(sourceURL: workingCopyURL, revision: revision)
        case .logCreateBranchTagFromRevision:
            return .createBranchTag(
                sourcePegURL: LogChangedPathPolicy.pegURL(workingCopyURL: workingCopyURL, revision: revision),
                revision: revision
            )
        case .logCheckoutOrExport:
            return .checkoutOrExport(
                sourcePegURL: LogChangedPathPolicy.pegURL(workingCopyURL: workingCopyURL, revision: revision),
                revision: revision
            )
        case .logUpdateItemToRevision,
             .logRevertToThisRevision,
             .logRevertChangesFromThisRevision:
            let relative: String
            if changedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                relative = "."
            } else {
                relative = LogChangedPathPolicy.workingCopyRelativePath(
                    changedPath: changedPath,
                    workingCopyURL: workingCopyURL
                )
                if relative.isEmpty { return nil }
            }
            switch command {
            case .logUpdateItemToRevision:
                return .updateToRevision(path: relative, revision: revision)
            case .logRevertToThisRevision:
                return .revertToRevision(path: relative, revision: revision)
            case .logRevertChangesFromThisRevision:
                return .revertChangesFromRevision(path: relative, revision: revision)
            default:
                return nil
            }
        default:
            break
        }

        let relative = LogChangedPathPolicy.workingCopyRelativePath(
            changedPath: changedPath,
            workingCopyURL: workingCopyURL
        )
        guard !relative.isEmpty else { return nil }

        switch command {
        case .logCompareWithWorkingCopy:
            return .compareWithWorkingCopy(path: relative, revision: revision)
        case .logCompareWithPrevious:
            return .compareWithPrevious(path: relative, revision: revision)
        case .logShowUnifiedDiff:
            return .showUnifiedDiff(path: relative, revision: revision)
        case .logSaveRevisionTo:
            return .saveRevision(path: relative, revision: revision)
        case .logOpen:
            return .openRevision(path: relative, revision: revision)
        case .logBlame:
            return .blame(path: relative, revision: revision)
        case .logBrowseRepository:
            let base = workingCopyURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let url = "\(base)/\(relative)"
            return .browseRepository(path: relative, revision: revision, repositoryURL: url)
        default:
            return nil
        }
    }
}
