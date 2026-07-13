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

/// 历史页一次性注入的 Diff 意图（路径 + 修订 + 对比模式），避免分字段竞态。
public struct PendingLogDiffIntent: Equatable, Sendable {
    public let path: String
    public let revision: Revision
    public let kind: PendingDiffCompareKind

    public init(path: String, revision: Revision, kind: PendingDiffCompareKind) {
        self.path = path
        self.revision = revision
        self.kind = kind
    }
}

/// Diff with URL 的一次性导航意图，避免 URL、目标和 revision 分散更新。
public struct PendingDiffWithURLIntent: Equatable, Sendable {
    public let target: String?
    public let url: String?
    public let revision: Revision?

    public init(target: String?, url: String?, revision: Revision?) {
        self.target = target
        self.url = url
        self.revision = revision
    }
}

public struct PendingRevisionGraphLogIntent: Equatable, Sendable {
    public let url: String
    public let revision: Revision

    public init(url: String, revision: Revision) {
        self.url = url
        self.revision = revision
    }
}

public enum PendingBlameMode: Equatable, Sendable {
    case standard
    case differences
}

public struct PendingBlameIntent: Equatable, Sendable {
    public let path: String
    public let revision: Revision?
    public let fromRevision: Revision?
    public let toRevision: Revision?
    public let mode: PendingBlameMode

    public init(path: String, revision: Revision?) {
        self.path = path
        self.revision = revision
        self.fromRevision = nil
        self.toRevision = revision
        self.mode = .standard
    }

    public init(
        path: String,
        fromRevision: Revision?,
        toRevision: Revision?,
        mode: PendingBlameMode
    ) {
        self.path = path
        self.revision = toRevision
        self.fromRevision = fromRevision
        self.toRevision = toRevision
        self.mode = mode
    }
}

public struct PendingChangelistIntent: Equatable, Sendable {
    public let paths: [String]

    public init(paths: [String]) {
        self.paths = paths
    }
}

public struct PendingExternalsIntent: Equatable, Sendable {
    public let path: String?

    public init(path: String?) {
        self.path = path
    }
}

public struct PendingTransferIntent: Equatable, Sendable {
    public let command: SvnCommandID
    public let path: String?
    public let url: String?
    public let revision: Revision?
    public let message: String?

    public init(command: SvnCommandID, path: String?, url: String?, revision: Revision?, message: String?) {
        self.command = command
        self.path = path
        self.url = url
        self.revision = revision
        self.message = message
    }
}

public struct PendingPatchIntent: Equatable, Sendable {
    public let command: SvnCommandID
    public let paths: [String]
    public let patchFile: String?

    public init(command: SvnCommandID, paths: [String], patchFile: String?) {
        self.command = command
        self.paths = paths
        self.patchFile = patchFile
    }
}

public struct PendingDeleteIntent: Equatable, Sendable {
    public let command: SvnCommandID
    public let paths: [String]

    public init(command: SvnCommandID, paths: [String]) {
        self.command = command
        self.paths = paths
    }
}

public struct PendingRevisionPropertiesIntent: Equatable, Sendable {
    public let command: SvnCommandID
    public let revision: Revision
    public let target: String?

    public init(command: SvnCommandID, revision: Revision, target: String?) {
        self.command = command
        self.revision = revision
        self.target = target
    }
}

/// 全局导航与自动化入口：深链 / CLI 伴生命令落到工作区 Mode 与 WC 打开意图。
@MainActor
public final class MacSvnAppNavigator: ObservableObject {
    @Published public var selectedRoute: MacSvnAppRoute
    @Published public var pendingOpenPath: String?
    @Published public var pendingCommitMessage: String?
    @Published public var pendingDiffPath: String?
    @Published public var pendingDiffRevision: Revision?
    @Published public var pendingDiffWithURL: PendingDiffWithURLIntent?
    /// 历史页 Diff 对比模式：与上一修订 / 与工作副本（L01/L02）。
    @Published public var pendingDiffCompareKind: PendingDiffCompareKind = .previous
    /// 历史页原子 Diff 意图（优先于分字段 pendingDiff*）。
    @Published public var pendingLogDiff: PendingLogDiffIntent?
    /// 历史 / Revision Graph → Blame（L07 / #9）。
    @Published public var pendingBlameIntent: PendingBlameIntent?
    @Published public var pendingRevisionGraphLog: PendingRevisionGraphLogIntent?
    @Published public var pendingChangelistIntent: PendingChangelistIntent?
    @Published public var pendingExternalsIntent: PendingExternalsIntent?
    /// CFM / ⌘K → 属性页预选路径（#35）。
    @Published public var pendingPropertyPath: String?
    /// CFM / 更新后 → 冲突工作区预选路径（#11）。
    @Published public var pendingConflictPath: String?
    /// Catalog Merge 命令进入合并向导；与冲突回跳保持原子区分。
    @Published public var pendingMergeWizard = false
    /// ⌘K / 自动化「标记为已解决」：进入冲突工作区后提示勾选批量 Resolved（#12）。
    @Published public var pendingResolvedHint = false
    /// CFM / ⌘K → 锁定页预选路径（#19–#21）。
    @Published public var pendingLockPaths: [String] = []
    /// CFM / ⌘K → 锁定页意图。
    @Published public var pendingLockIntent: LockActionIntent?
    /// 历史 → 仓库浏览器 URL（L08）。
    @Published public var pendingBrowseURL: String?
    @Published public var pendingBrowseRevision: Revision?
    /// 从日志页带入 Release Notes 页的候选条目。
    @Published public var pendingReleaseNotesEntries: [LogEntry]?
    /// ⌘K 无结构化命中时带入 AI Chat 的自然语言 query（FR-EX-04）。
    @Published public var pendingAIChatQuery: String?
    @Published public var pendingTransferIntent: PendingTransferIntent?
    @Published public var pendingPatchIntent: PendingPatchIntent?
    @Published public var pendingDeleteIntent: PendingDeleteIntent?
    @Published public var pendingRevisionPropertiesIntent: PendingRevisionPropertiesIntent?
    @Published public var pendingCreateRepository = false
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
        // 锁定命令携带的是 WC 内相对路径，不应触发「打开工作副本」深链。
        let isLockCommand = Self.lockIntent(for: command) != nil
        let isPatchCommand = command == .createPatch || command == .applyPatch
        let isPathInspectorCommand = command == .blame || command == .compareRevisions
            || command == .properties || command == .externals
            || command == .deleteKeepLocal || command == .deleteUnversioned
        let isChangelistCommand = command == .changeLists
        let canInferWorkingCopyPath = command != .diffWithURL || (
            paths.count >= 2 && (paths[0] as NSString).isAbsolutePath
        )
        if !isLockCommand, !isPatchCommand, !isPathInspectorCommand, !isChangelistCommand,
           canInferWorkingCopyPath,
           let firstPath = paths.first, !firstPath.isEmpty {
            pendingOpenPath = firstPath
        }
        if command != .diffWithURL {
            if paths.count >= 2, !paths[1].isEmpty {
                // 第二路径常用于 Diff 目标文件
                pendingDiffPath = paths[1]
            } else if let only = paths.first, command == .diff {
                // 仅 Diff 注入 pendingDiffPath；CFM 等命令不应误触发 Diff 加载
                pendingDiffPath = only
            }
        }

        if command == .diffWithURL {
            pendingDiffPath = nil
            pendingDiffRevision = nil
            pendingDiffCompareKind = .previous
            pendingLogDiff = nil
            pendingDiffWithURL = PendingDiffWithURLIntent(
                target: Self.diffWithURLTarget(paths),
                url: options.url,
                revision: options.revision
            )
        }

        if let message = options.message, !message.isEmpty {
            pendingCommitMessage = message
        }
        if let revision = options.revision, command != .diffWithURL {
            pendingDiffRevision = revision
        }

        // #11/#12：冲突相关命令注入预选路径与 Resolved 提示，避免仅「打开合并页」语义空洞。
        if command == .editConflicts || command == .resolved {
            if let first = paths.first, !first.isEmpty {
                pendingConflictPath = first
            }
            pendingResolvedHint = (command == .resolved)
        }

        if command == .merge {
            pendingMergeWizard = true
        }

        if command == .changeLists {
            pendingChangelistIntent = PendingChangelistIntent(paths: paths.filter { !$0.isEmpty })
        }

        if command == .externals {
            pendingExternalsIntent = PendingExternalsIntent(path: paths.first(where: { !$0.isEmpty }))
        }

        if command == .createRepositoryHere {
            pendingCreateRepository = true
        }

        if [.checkout, .export, .importToRepository, .importInPlace, .relocate, .removeFromVersionControl].contains(command) {
            pendingTransferIntent = PendingTransferIntent(
                command: command,
                path: paths.first,
                url: options.url,
                revision: options.revision,
                message: options.message
            )
        }

        if isPatchCommand {
            pendingPatchIntent = PendingPatchIntent(
                command: command,
                paths: paths,
                patchFile: options.extras["patchFile"]
            )
        }

        if command == .deleteKeepLocal || command == .deleteUnversioned {
            pendingDeleteIntent = PendingDeleteIntent(command: command, paths: paths)
        }

        if command == .compareRevisions {
            let fromRevision = options.extras["fromRevision"].flatMap(Int.init).flatMap {
                $0 > 0 ? Revision($0) : nil
            }
            let toRevision = options.revision
                ?? options.extras["toRevision"].flatMap(Int.init).flatMap {
                    $0 > 0 ? Revision($0) : nil
                }
            pendingBlameIntent = PendingBlameIntent(
                path: paths.first ?? "",
                fromRevision: fromRevision,
                toRevision: toRevision,
                mode: .differences
            )
        }

        if (command == .logEditAuthorOrMessage || command == .logShowRevisionProperties),
           let revision = options.revision {
            pendingRevisionPropertiesIntent = PendingRevisionPropertiesIntent(
                command: command,
                revision: revision,
                target: options.url
            )
        }

        if let path = paths.first, !path.isEmpty {
            if command == .blame {
                pendingBlameIntent = PendingBlameIntent(path: path, revision: options.revision)
            } else if command == .properties {
                pendingPropertyPath = path
            }
        }

        // #19–#21：锁定命令注入路径与意图。
        if let lockIntent = Self.lockIntent(for: command) {
            pendingLockPaths = paths.filter { !$0.isEmpty }
            pendingLockIntent = lockIntent
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
        case .repairFilenameCaseConflict, .changeLists:
            return .changes
        case .diff, .diffWithURL:
            return .diff
        case .revisionGraph:
            return .revisionGraph
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
        case .createPatch, .applyPatch:
            return .shelve
        case .checkout:
            return .repositoryBrowser
        case .export, .importToRepository, .importInPlace, .relocate,
             .removeFromVersionControl:
            return .repositoryBrowser
        case .createRepositoryHere:
            return .repositoryBrowser
        case .deleteKeepLocal, .deleteUnversioned:
            return .changes
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

    public static func lockIntent(for command: SvnCommandID) -> LockActionIntent? {
        switch command {
        case .getLock: return .getLock
        case .releaseLock: return .releaseLock
        case .breakLock: return .breakLock
        default: return nil
        }
    }

    private static func diffWithURLTarget(_ paths: [String]) -> String? {
        let nonEmpty = paths.filter { !$0.isEmpty }
        if nonEmpty.count == 1 {
            return nonEmpty[0]
        }
        guard nonEmpty.count == 2, (nonEmpty[0] as NSString).isAbsolutePath else {
            return nil
        }
        return nonEmpty[1]
    }

    @discardableResult
    public func handle(deepLink action: MacSvnDeepLinkAction) -> SvnCommandPerformResult? {
        switch action {
        case .open(let path):
            pendingOpenPath = path
            selectedRoute = .changes
            lastAutomationMessage = "深链打开：\(path)"
            return nil
        case .command(let command, let paths):
            let result = perform(command: command, paths: paths)
            lastAutomationMessage = "Finder 命令：\(SvnCommandCatalog.descriptor(for: command)?.displayName ?? command.rawValue)"
            return result
        case .log(let target, _):
            apply(target: target)
            selectedRoute = .log
            lastAutomationMessage = "深链跳转历史"
            return nil
        case .diff(let target, let range):
            apply(target: target)
            if case .path(let path) = target {
                pendingDiffPath = path
            }
            pendingDiffRevision = range?.end
            // Diff 归入变更工作区，路径经 pendingDiffPath 注入
            selectedRoute = .changes
            lastAutomationMessage = "深链跳转 Diff"
            return nil
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

    public func consumePendingDiffWithURL() -> PendingDiffWithURLIntent? {
        let value = pendingDiffWithURL
        pendingDiffWithURL = nil
        return value
    }

    public func consumePendingDiffCompareKind() -> PendingDiffCompareKind {
        let value = pendingDiffCompareKind
        pendingDiffCompareKind = .previous
        return value
    }

    public func consumePendingLogDiff() -> PendingLogDiffIntent? {
        let value = pendingLogDiff
        pendingLogDiff = nil
        return value
    }

    public func consumePendingBlameIntent() -> PendingBlameIntent? {
        let value = pendingBlameIntent
        pendingBlameIntent = nil
        return value
    }

    public func consumePendingRevisionGraphLog() -> PendingRevisionGraphLogIntent? {
        let value = pendingRevisionGraphLog
        pendingRevisionGraphLog = nil
        return value
    }

    public func consumePendingChangelistIntent() -> PendingChangelistIntent? {
        let value = pendingChangelistIntent
        pendingChangelistIntent = nil
        return value
    }

    public func consumePendingExternalsIntent() -> PendingExternalsIntent? {
        let value = pendingExternalsIntent
        pendingExternalsIntent = nil
        return value
    }

    public func consumePendingDeleteIntent() -> PendingDeleteIntent? {
        let value = pendingDeleteIntent
        pendingDeleteIntent = nil
        return value
    }

    public func consumePendingRevisionPropertiesIntent() -> PendingRevisionPropertiesIntent? {
        let value = pendingRevisionPropertiesIntent
        pendingRevisionPropertiesIntent = nil
        return value
    }

    public func consumePendingPropertyPath() -> String? {
        let value = pendingPropertyPath
        pendingPropertyPath = nil
        return value
    }

    public func consumePendingConflictPath() -> String? {
        let value = pendingConflictPath
        pendingConflictPath = nil
        return value
    }

    public func consumePendingResolvedHint() -> Bool {
        let value = pendingResolvedHint
        pendingResolvedHint = false
        return value
    }

    public func consumePendingMergeWizard() -> Bool {
        let value = pendingMergeWizard
        pendingMergeWizard = false
        return value
    }

    public func consumePendingCreateRepository() -> Bool {
        let value = pendingCreateRepository
        pendingCreateRepository = false
        return value
    }

    public func openMergeConflicts(paths: [String]) {
        pendingMergeWizard = false
        pendingConflictPath = paths.first(where: { !$0.isEmpty })
        selectedRoute = .merge
        lastAutomationMessage = "合并产生冲突：已打开冲突工作区"
    }

    public func consumePendingLockPaths() -> [String] {
        let value = pendingLockPaths
        pendingLockPaths = []
        return value
    }

    public func consumePendingLockIntent() -> LockActionIntent? {
        let value = pendingLockIntent
        pendingLockIntent = nil
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

    public func consumePendingTransferIntent() -> PendingTransferIntent? {
        let value = pendingTransferIntent
        pendingTransferIntent = nil
        return value
    }

    public func consumePendingPatchIntent() -> PendingPatchIntent? {
        let value = pendingPatchIntent
        pendingPatchIntent = nil
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
