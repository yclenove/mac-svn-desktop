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
}

/// 日志右键动作意图（L01–L08；L03 属 T3，本策略不产出）。
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
}

/// 从 Catalog ID + 上下文解析可执行意图。
public enum LogContextActionPolicy: Sendable {
    public static let t2ActionIDs: [SvnCommandID] = [
        .logCompareWithWorkingCopy,
        .logCompareWithPrevious,
        .logShowUnifiedDiff,
        .logSaveRevisionTo,
        .logOpen,
        .logBlame,
        .logBrowseRepository,
    ]

    public static func intent(
        command: SvnCommandID,
        changedPath: String,
        revision: Revision,
        workingCopyURL: String
    ) -> LogContextActionIntent? {
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
