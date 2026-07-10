import Foundation
import MacSvnCore

/// 全局导航与自动化入口：深链 / CLI 伴生命令落到侧边栏路由与 WC 打开意图。
@MainActor
public final class MacSvnAppNavigator: ObservableObject {
    @Published public var selectedRoute: MacSvnAppRoute
    @Published public var pendingOpenPath: String?
    @Published public var pendingCommitMessage: String?
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
            apply(target: target, fallbackRoute: .log)
            selectedRoute = .log
            lastAutomationMessage = "深链跳转日志"
        case .diff(let target, _):
            apply(target: target, fallbackRoute: .diff)
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

    private func apply(target: MacSvnAutomationTarget, fallbackRoute _: MacSvnAppRoute) {
        switch target {
        case .path(let path):
            pendingOpenPath = path
        case .repositoryURL:
            // 远端 URL 由对应功能页自行使用；此处仅切换路由
            break
        }
    }
}
