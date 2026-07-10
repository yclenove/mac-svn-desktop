#if canImport(FinderSync)
import Cocoa
import FinderSync

/// Finder Sync 扩展骨架：供 Xcode 扩展 target 引用。
/// SwiftPM 阶段不编译本文件；合入 Xcode 包装工程后启用。
final class MacSvnFinderSync: FIFinderSync {
    override init() {
        super.init()
        // 生产环境应从 App Group / 主应用导出的 WC 根目录列表注册监控路径
        FIFinderSyncController.default().directoryURLs = []
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "MacSVN")
        menu.addItem(withTitle: "在 MacSVN 中打开", action: #selector(openInMacSVN), keyEquivalent: "")
        menu.addItem(withTitle: "提交…", action: #selector(commitInMacSVN), keyEquivalent: "")
        menu.addItem(withTitle: "查看 Diff", action: #selector(diffInMacSVN), keyEquivalent: "")
        return menu
    }

    @objc private func openInMacSVN() {
        openDeepLink(route: "open")
    }

    @objc private func commitInMacSVN() {
        openDeepLink(route: "open")
    }

    @objc private func diffInMacSVN() {
        openDeepLink(route: "diff")
    }

    private func openDeepLink(route: String) {
        guard let url = FIFinderSyncController.default().targetedURL() else { return }
        var components = URLComponents()
        components.scheme = "macsvn"
        components.host = route
        components.queryItems = [URLQueryItem(name: "path", value: url.path)]
        if let deepLink = components.url {
            NSWorkspace.shared.open(deepLink)
        }
    }
}
#endif
