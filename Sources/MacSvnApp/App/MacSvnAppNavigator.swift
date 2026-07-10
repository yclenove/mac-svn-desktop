import Foundation
import MacSvnCore

/// 全局导航与自动化入口：深链 / CLI 伴生命令落到侧边栏路由与 WC 打开意图。
@MainActor
public final class MacSvnAppNavigator: ObservableObject {
    @Published public var selectedRoute: MacSvnAppRoute
    @Published public var pendingOpenPath: String?
    @Published public var pendingCommitMessage: String?
    @Published public var pendingDiffPath: String?
    @Published public var pendingDiffRevision: Revision?
    /// 从日志页带入 Release Notes 页的候选条目。
    @Published public var pendingReleaseNotesEntries: [LogEntry]?
    /// ⌘K 无结构化命中时带入 AI Chat 的自然语言 query（FR-EX-04）。
    @Published public var pendingAIChatQuery: String?
    @Published public var lastAutomationMessage: String?

    public init(selectedRoute: MacSvnAppRoute = .workspace) {
        self.selectedRoute = selectedRoute
    }

    public func handle(deepLink action: MacSvnDeepLinkAction) {
        switch action {
        case .open(let path):
            pendingOpenPath = path
            selectedRoute = .workspace
            lastAutomationMessage = "深链打开：\(path)"
        case .log(let target, _):
            apply(target: target)
            selectedRoute = .log
            lastAutomationMessage = "深链跳转日志"
        case .diff(let target, let range):
            apply(target: target)
            if case .path(let path) = target {
                pendingDiffPath = path
            }
            pendingDiffRevision = range?.end
            selectedRoute = .diff
            lastAutomationMessage = "深链跳转 Diff"
        }
    }

    public func handle(cli command: MacSvnCLICommand) {
        switch command {
        case .open(let path):
            pendingOpenPath = path
            selectedRoute = .workspace
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
