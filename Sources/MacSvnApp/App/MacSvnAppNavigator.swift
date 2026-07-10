import Foundation
import MacSvnCore

/// Catalog 命令经 Navigator 执行后的结果。
public enum SvnCommandPerformResult: Equatable, Sendable {
    case navigated(to: MacSvnAppRoute)
    case unimplemented(SvnCommandID)
}

/// 历史页注入 Diff 时的对比模式（L01 / L02）。
public enum PendingDiffCompareKind: Equatable, Sendable {
    /// 与上一修订：`r(n-1):r(n)`
    case previous
    /// 与工作副本：`r(n)` vs WC（r2 留空）
    case workingCopy
}

/// 全局导航与自动化入口：深链 / CLI 伴生命令落到工作区 Mode 与 WC 打开意图。
@MainActor
public final class MacSvnAppNavigator: ObservableObject {
    @Published public var selectedRoute: MacSvnAppRoute
    @Published public var pendingOpenPath: String?
    @Published public var pendingCommitMessage: String?
    @Published public var pendingDiffPath: String?
    @Published public var pendingDiffRevision: Revision?
    /// 历史页 Diff 对比模式：与上一修订 / 与工作副本（L01/L02）。
    @Published public var pendingDiffCompareKind: PendingDiffCompareKind = .previous
    /// 历史 → Blame（L07）。
    @Published public var pendingBlamePath: String?
    /// 历史 → 仓库浏览器 URL（L08）。
    @Published public var pendingBrowseURL: String?
    @Published public var pendingBrowseRevision: Revision?
    /// 从日志页带入 Release Notes 页的候选条目。
    @Published public var pendingReleaseNotesEntries: [LogEntry]?
    /// ⌘K 无结构化命中时带入 AI Chat 的自然语言 query（FR-EX-04）。
    @Published public var pendingAIChatQuery: String?
    @Published public var lastAutomationMessage: String?
    /// 最近一次 `perform(command:)` 结果（供 UI / 测试观察）。
    @Published public var lastCommandResult: SvnCommandPerformResult?

    public var selectedMode: MacSvnWorkspaceMode {
        MacSvnWorkspaceMode(route: selectedRoute)
    }

    public init(selectedRoute: MacSvnAppRoute = .changes) {
        self.selectedRoute = selectedRoute
    }

    public func selectMode(_ mode: MacSvnWorkspaceMode) {
        selectedRoute = mode.primaryRoute
    }

    public func selectRoute(_ route: MacSvnAppRoute) {
        selectedRoute = route
    }

    public func dismissAutomationBanner() {
        lastAutomationMessage = nil
    }

    /// 统一命令入口：对齐 `SvnCommandCatalog`。
    ///
    /// - 已接线命令：导航到对应 Route，并可选注入 paths / options。
    /// - 未接线命令（T0 允许）：返回 `.unimplemented`，并设置可读提示，**不**假装成功。
    @discardableResult
    public func perform(
        command: SvnCommandID,
        paths: [String] = [],
        options: SvnCommandOptions = SvnCommandOptions()
    ) -> SvnCommandPerformResult {
        if let firstPath = paths.first, !firstPath.isEmpty {
            pendingOpenPath = firstPath
        }
        if paths.count >= 2, !paths[1].isEmpty {
            // 第二路径常用于 Diff 目标文件
            pendingDiffPath = paths[1]
        } else if let only = paths.first, command == .diff {
            // 仅 Diff 注入 pendingDiffPath；CFM 等命令不应误触发 Diff 加载
            pendingDiffPath = only
        }

        if let message = options.message, !message.isEmpty {
            pendingCommitMessage = message
        }
        if let revision = options.revision {
            pendingDiffRevision = revision
        }

        guard let route = Self.route(for: command) else {
            let name = SvnCommandCatalog.descriptor(for: command)?.displayName ?? command.rawValue
            lastAutomationMessage = "未实现：\(name)"
            let result = SvnCommandPerformResult.unimplemented(command)
            lastCommandResult = result
            return result
        }

        selectedRoute = route
        let name = SvnCommandCatalog.descriptor(for: command)?.displayName ?? command.rawValue
        lastAutomationMessage = "命令：\(name)"
        let result = SvnCommandPerformResult.navigated(to: route)
        lastCommandResult = result
        return result
    }

    /// T0 已可导航的命令 → Route 映射；其余一律 unimplemented。
    public static func route(for command: SvnCommandID) -> MacSvnAppRoute? {
        switch command {
        case .commit:
            return .commit
        case .update, .updateToRevision, .checkForModifications, .add, .delete, .revert, .cleanup,
             .rename, .addToIgnoreList, .copyMove, .repairMoveCopy:
            return .changes
        case .diff, .diffWithURL:
            return .diff
        case .showLog, .saveRevisionOpen:
            return .log
        case .repoBrowser:
            return .repositoryBrowser
        case .editConflicts, .resolved, .merge, .mergeReintegrate, .mergeRevisionTo:
            return .merge
        case .branchTag, .switchBranch:
            return .branches
        case .blame, .compareRevisions:
            return .blame
        case .properties, .externals:
            return .properties
        case .getLock, .releaseLock, .breakLock:
            return .locks
        case .shelve:
            return .shelve
        case .checkout, .export, .importToRepository, .importInPlace, .relocate,
             .createRepositoryHere, .removeFromVersionControl, .createPatch, .applyPatch,
             .revisionGraph, .changeLists, .deleteKeepLocal, .deleteUnversioned,
             .repairFilenameCaseConflict:
            return nil
        case .logCompareWithWorkingCopy, .logCompareWithPrevious, .logCompareAndBlame,
             .logShowUnifiedDiff, .logSaveRevisionTo, .logOpen, .logBlame, .logBrowseRepository,
             .logCreateBranchTagFromRevision, .logUpdateItemToRevision, .logRevertToThisRevision,
             .logRevertChangesFromThisRevision, .logMergeRevisionTo, .logCheckoutOrExport,
             .logEditAuthorOrMessage, .logShowRevisionProperties, .logCopyToClipboard,
             .logFilterStatisticsOffline, .logActionsColumnIcons, .logFetchStrategy:
            // 日志动作最终应在历史页上下文执行；T0 先导航到日志页作为可达入口
            return .log
        }
    }

    public func handle(deepLink action: MacSvnDeepLinkAction) {
        switch action {
        case .open(let path):
            pendingOpenPath = path
            selectedRoute = .changes
            lastAutomationMessage = "深链打开：\(path)"
        case .log(let target, _):
            apply(target: target)
            selectedRoute = .log
            lastAutomationMessage = "深链跳转历史"
        case .diff(let target, let range):
            apply(target: target)
            if case .path(let path) = target {
                pendingDiffPath = path
            }
            pendingDiffRevision = range?.end
            // Diff 归入变更工作区，路径经 pendingDiffPath 注入
            selectedRoute = .changes
            lastAutomationMessage = "深链跳转 Diff"
        }
    }

    public func handle(cli command: MacSvnCLICommand) {
        switch command {
        case .open(let path):
            pendingOpenPath = path
            selectedRoute = .changes
            lastAutomationMessage = "CLI open：\(path)"
        case .status(let path):
            pendingOpenPath = path
            selectedRoute = .changes
            lastAutomationMessage = "CLI status：\(path)"
        case .commitUI(let path, let message):
            pendingOpenPath = path
            pendingCommitMessage = message
            selectedRoute = .commit
            lastAutomationMessage = "CLI commit-ui：\(path)"
        }
    }

    public func consumePendingOpenPath() -> String? {
        let value = pendingOpenPath
        pendingOpenPath = nil
        return value
    }

    public func consumePendingCommitMessage() -> String? {
        let value = pendingCommitMessage
        pendingCommitMessage = nil
        return value
    }

    public func consumePendingDiffPath() -> String? {
        let value = pendingDiffPath
        pendingDiffPath = nil
        return value
    }

    public func consumePendingDiffRevision() -> Revision? {
        let value = pendingDiffRevision
        pendingDiffRevision = nil
        return value
    }

    public func consumePendingDiffCompareKind() -> PendingDiffCompareKind {
        let value = pendingDiffCompareKind
        pendingDiffCompareKind = .previous
        return value
    }

    public func consumePendingBlamePath() -> String? {
        let value = pendingBlamePath
        pendingBlamePath = nil
        return value
    }

    public func consumePendingBrowseURL() -> String? {
        let value = pendingBrowseURL
        pendingBrowseURL = nil
        return value
    }

    public func consumePendingBrowseRevision() -> Revision? {
        let value = pendingBrowseRevision
        pendingBrowseRevision = nil
        return value
    }

    public func consumePendingAIChatQuery() -> String? {
        let value = pendingAIChatQuery
        pendingAIChatQuery = nil
        return value
    }

    /// ⌘K 无匹配时转入 AI Chat 并携带原 query。
    public func handoffCommandPaletteQueryToAIChat(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingAIChatQuery = trimmed
        selectedRoute = .aiAssistant
        lastAutomationMessage = "⌘K 转 AI：\(trimmed)"
    }

    private func apply(target: MacSvnAutomationTarget) {
        switch target {
        case .path(let path):
            pendingOpenPath = path
        case .repositoryURL:
            break
        }
    }
}
