import Cocoa
import FinderSync
import MacSvnCore

/// Finder Sync 扩展：角标 + 右键深链（FR-EX-05）。
/// 注意：为读取任意 WC 并调用 `svn status`，本扩展关闭 App Sandbox（开发工具常见做法）。
final class MacSvnFinderSync: FIFinderSync {
    private let presentationBuilder = FinderSyncPresentationBuilder()
    private let deepLinkBuilder = FinderSyncDeepLinkBuilder()
    private let statusCache = FinderSyncStatusCache()
    private var rootsFileObserver: DispatchSourceFileSystemObject?

    override init() {
        super.init()
        registerBadgeImages()
        reloadMonitoredDirectories()
        watchRootsFile()
    }

    deinit {
        rootsFileObserver?.cancel()
    }

    override func requestBadgeIdentifier(for url: URL) {
        let path = url.path
        let builder = presentationBuilder
        let cache = statusCache
        Task {
            guard let root = await cache.workingCopyRoot(containing: path) else {
                await MainActor.run {
                    FIFinderSyncController.default().setBadgeIdentifier("", for: url)
                }
                return
            }

            let statuses = await cache.statuses(for: root)
            let relative = MacSvnFinderSync.relativePath(of: path, under: root) ?? "."
            let presentation = builder.presentation(for: relative, statuses: statuses)
            let identifier = presentation.badge == .normal ? "" : presentation.badge.rawValue
            await MainActor.run {
                FIFinderSyncController.default().setBadgeIdentifier(identifier, for: url)
            }
        }
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: ProductBranding.displayName)
        let targetURL = FIFinderSyncController.default().targetedURL()
            ?? FIFinderSyncController.default().selectedItemURLs()?.first
        let path = targetURL?.path ?? ""

        // Finder 菜单回调是同步的：固定提供深链入口；角标侧仍用 PresentationBuilder 精细态。
        let items: [(FinderSyncMenuActionID, String)] = [
            (.update, "更新"),
            (.commit, "提交"),
            (.log, "查看日志"),
            (.diff, "查看差异"),
            (.revert, "还原"),
            (.resolve, "解决冲突"),
        ]
        for (actionID, title) in items {
            let item = NSMenuItem(title: title, action: #selector(handleMenuAction(_:)), keyEquivalent: "")
            item.representedObject = MenuPayload(actionID: actionID, path: path)
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @objc private func handleMenuAction(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? MenuPayload else { return }
        let linkPath = payload.path.isEmpty
            ? (FIFinderSyncController.default().targetedURL()?.path ?? "")
            : payload.path
        guard let url = deepLinkBuilder.url(for: payload.actionID, path: linkPath) else { return }
        NSWorkspace.shared.open(url)
    }

    private func registerBadgeImages() {
        let controller = FIFinderSyncController.default()
        let badges: [(FinderSyncBadge, NSColor, String)] = [
            (.modified, .systemOrange, "修改"),
            (.added, .systemGreen, "新增"),
            (.deleted, .systemRed, "删除"),
            (.missing, .systemRed, "缺失"),
            (.conflicted, .systemPurple, "冲突"),
            (.replaced, .systemOrange, "替换"),
            (.unversioned, .systemGray, "未版本"),
            (.ignored, .systemGray, "忽略"),
            (.external, .systemBlue, "外部"),
            (.incomplete, .systemYellow, "不完整"),
            (.obstructed, .systemRed, "阻碍"),
        ]
        for (badge, color, label) in badges {
            controller.setBadgeImage(Self.makeBadgeImage(color: color), label: label, forBadgeIdentifier: badge.rawValue)
        }
    }

    private func reloadMonitoredDirectories() {
        let roots = loadRoots()
        let cache = statusCache
        Task {
            await cache.updateRoots(roots)
        }
        FIFinderSyncController.default().directoryURLs = Set(roots.map { URL(fileURLWithPath: $0, isDirectory: true) })
    }

    private func loadRoots() -> [String] {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(ProductBranding.supportDirectoryName)", isDirectory: true)
        let fileURL = FinderSyncRootsExporter.fileURL(in: support)
        return (try? FinderSyncRootsExporter.load(from: fileURL)) ?? []
    }

    private func watchRootsFile() {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(ProductBranding.supportDirectoryName)", isDirectory: true)
        let fileURL = FinderSyncRootsExporter.fileURL(in: support)
        let path = fileURL.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.reloadMonitoredDirectories()
        }
        source.setCancelHandler {
            close(fd)
        }
        rootsFileObserver = source
        source.resume()
    }

    private static func relativePath(of absolutePath: String, under root: String) -> String? {
        let normalizedRoot = (root as NSString).standardizingPath
        let normalizedPath = (absolutePath as NSString).standardizingPath
        guard normalizedPath == normalizedRoot || normalizedPath.hasPrefix(normalizedRoot + "/") else {
            return nil
        }
        if normalizedPath == normalizedRoot {
            return "."
        }
        return String(normalizedPath.dropFirst(normalizedRoot.count + 1))
    }

    private static func makeBadgeImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 12, height: 12)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

private struct MenuPayload {
    let actionID: FinderSyncMenuActionID
    let path: String
}

/// 按 WC 根缓存 `svn status --xml` 结果，避免 Finder 刷角标时频繁打进程。
actor FinderSyncStatusCache {
    private var roots: [String] = []
    private var cache: [String: (date: Date, statuses: [FileStatus])] = [:]
    private let ttl: TimeInterval = 8

    func updateRoots(_ roots: [String]) {
        self.roots = roots.map { ($0 as NSString).standardizingPath }
    }

    func workingCopyRoot(containing path: String) -> String? {
        let normalized = (path as NSString).standardizingPath
        return roots
            .filter { normalized == $0 || normalized.hasPrefix($0 + "/") }
            .max(by: { $0.count < $1.count })
    }

    func cachedStatuses(for root: String) -> [FileStatus]? {
        let key = (root as NSString).standardizingPath
        guard let entry = cache[key], Date().timeIntervalSince(entry.date) < ttl else {
            return nil
        }
        return entry.statuses
    }

    func statuses(for root: String) async -> [FileStatus] {
        let key = (root as NSString).standardizingPath
        if let cached = cachedStatuses(for: key) {
            return cached
        }
        let loaded = await Self.runSvnStatus(wc: URL(fileURLWithPath: key, isDirectory: true))
        cache[key] = (Date(), loaded)
        return loaded
    }

    private static func runSvnStatus(wc: URL) async -> [FileStatus] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["svn", "status", "--xml", "--non-interactive"]
                process.currentDirectoryURL = wc
                process.environment = ProcessInfo.processInfo.environment.merging([
                    "LC_ALL": "C",
                    "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:"
                        + (ProcessInfo.processInfo.environment["PATH"] ?? ""),
                ]) { _, new in new }

                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    let statuses = (try? StatusXMLParser.parse(data)) ?? []
                    continuation.resume(returning: statuses)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
}
