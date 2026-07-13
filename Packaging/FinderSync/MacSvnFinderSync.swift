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
            guard let context = await cache.requestContext(containing: path) else {
                await MainActor.run {
                    FIFinderSyncController.default().setBadgeIdentifier("", for: url)
                }
                return
            }

            let root = context.root
            let relative = MacSvnFinderSync.relativePath(of: path, under: root) ?? "."
            guard await cache.collectsBadges() else {
                await MainActor.run {
                    FIFinderSyncController.default().setBadgeIdentifier("", for: url)
                }
                return
            }
            guard let statuses = await cache.statuses(for: root, requestedTarget: relative) else {
                await MainActor.run {
                    FIFinderSyncController.default().setBadgeIdentifier("", for: url)
                }
                return
            }
            let presentation = builder.presentation(
                for: relative,
                statuses: statuses,
                overlaySettings: context.overlaySettings
            )
            await MainActor.run {
                FIFinderSyncController.default().setBadgeIdentifier(presentation.badge.rawValue, for: url)
            }
        }
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: ProductBranding.displayName)
        let paths = selectedMenuPaths()

        // Finder 菜单回调是同步的：固定提供深链入口；角标侧仍用 PresentationBuilder 精细态。
        let items: [(SvnCommandID, String)] = [
            (.update, "更新"),
            (.commit, "提交"),
            (.showLog, "查看日志"),
            (.diff, "查看差异"),
            (.revert, "还原"),
            (.resolved, "解决冲突"),
        ]
        for (commandID, title) in items {
            let item = NSMenuItem(title: title, action: #selector(handleMenuAction(_:)), keyEquivalent: "")
            item.representedObject = MenuPayload(commandID: commandID, paths: paths)
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let extendedItem = NSMenuItem(title: "更多命令…", action: nil, keyEquivalent: "")
        let extendedMenu = NSMenu(title: "更多命令…")
        let extendedCommandIDs: [SvnCommandID] = [
            .add,
            .delete,
            .properties,
        ] + SvnCommandCatalog.extendedMenuCommands.map(\.id)
        for commandID in extendedCommandIDs {
            guard let descriptor = SvnCommandCatalog.descriptor(for: commandID) else { continue }
            let item = NSMenuItem(
                title: descriptor.displayName,
                action: #selector(handleMenuAction(_:)),
                keyEquivalent: ""
            )
            item.representedObject = MenuPayload(commandID: commandID, paths: paths)
            item.target = self
            extendedMenu.addItem(item)
        }
        extendedItem.submenu = extendedMenu
        menu.addItem(extendedItem)
        return menu
    }

    @objc private func handleMenuAction(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? MenuPayload else { return }
        let linkPaths = payload.paths.isEmpty ? selectedMenuPaths() : payload.paths
        let url: URL?
        if let commandID = payload.commandID {
            url = deepLinkBuilder.commandURL(for: commandID, paths: linkPaths)
        } else if let actionID = payload.actionID {
            url = deepLinkBuilder.url(for: actionID, path: linkPaths.first ?? "")
        } else {
            return
        }
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    private func selectedMenuPaths() -> [String] {
        let selectedPaths = FIFinderSyncController.default()
            .selectedItemURLs()?
            .map(\.path)
            .filter { !$0.isEmpty } ?? []
        if !selectedPaths.isEmpty {
            return selectedPaths
        }
        guard let targetedPath = FIFinderSyncController.default().targetedURL()?.path,
              !targetedPath.isEmpty else {
            return []
        }
        return [targetedPath]
    }

    private func registerBadgeImages() {
        let controller = FIFinderSyncController.default()
        let badges: [(FinderSyncBadge, NSColor, String, String)] = [
            (.normal, .systemGreen, "checkmark.circle.fill", "正常"),
            (.modified, .systemOrange, "pencil.circle.fill", "修改"),
            (.added, .systemGreen, "plus.circle.fill", "新增"),
            (.deleted, .systemRed, "minus.circle.fill", "删除"),
            (.missing, .systemRed, "questionmark.circle.fill", "缺失"),
            (.conflicted, .systemPurple, "exclamationmark.triangle.fill", "冲突"),
            (.replaced, .systemOrange, "arrow.triangle.2.circlepath.circle.fill", "替换"),
            (.locked, .systemBlue, "lock.fill", "已锁定"),
            (.needsLock, .systemYellow, "lock.open.fill", "需要锁定"),
            (.unversioned, .systemGray, "questionmark.circle.fill", "未版本"),
            (.ignored, .systemGray, "eye.slash.fill", "忽略"),
            (.shallow, .systemYellow, "arrow.down.to.line.compact", "稀疏深度"),
            (.nested, .systemTeal, "square.stack.3d.up.fill", "嵌套工作副本"),
            (.external, .systemBlue, "link.circle.fill", "外部项"),
            (.switched, .systemIndigo, "arrow.triangle.branch", "已切换"),
            (.mergeInfo, .systemTeal, "arrow.triangle.merge", "仅合并信息"),
            (.incomplete, .systemYellow, "ellipsis.circle.fill", "不完整"),
            (.obstructed, .systemRed, "nosign", "阻碍"),
        ]
        for (badge, color, symbol, label) in badges {
            controller.setBadgeImage(
                Self.makeBadgeImage(color: color, symbolName: symbol),
                label: label,
                forBadgeIdentifier: badge.rawValue
            )
        }
    }

    private func reloadMonitoredDirectories() {
        let configuration = loadConfiguration()
        let cache = statusCache
        let directoryURLs = Set(
            configuration.overlaySettings
                .monitoredDirectories(for: configuration.roots)
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
        )
        Task {
            await cache.updateConfiguration(configuration)
            await MainActor.run {
                FIFinderSyncController.default().directoryURLs = directoryURLs
            }
        }
    }

    private func loadConfiguration() -> FinderSyncRootsFile {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(ProductBranding.supportDirectoryName)", isDirectory: true)
        let fileURL = FinderSyncRootsExporter.fileURL(in: support)
        return (try? FinderSyncRootsExporter.loadConfiguration(from: fileURL)) ?? FinderSyncRootsFile()
    }

    private func watchRootsFile() {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(ProductBranding.supportDirectoryName)", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let directoryPath = support.path
        let fd = open(directoryPath, O_EVTONLY)
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

    private static func makeBadgeImage(color: NSColor, symbolName: String) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let image = NSImage(size: size)
            image.lockFocus()
            color.set()
            symbol.draw(
                in: NSRect(origin: .zero, size: size),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            image.unlockFocus()
            image.isTemplate = false
            return image
        }
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
    let actionID: FinderSyncMenuActionID?
    let commandID: SvnCommandID?
    let paths: [String]

    init(actionID: FinderSyncMenuActionID, path: String) {
        self.actionID = actionID
        self.commandID = nil
        self.paths = [path]
    }

    init(commandID: SvnCommandID, paths: [String]) {
        self.actionID = nil
        self.commandID = commandID
        self.paths = paths
    }
}

private struct FinderSyncRequestContext: Sendable {
    let root: String
    let overlaySettings: FinderSyncOverlaySettings
}

/// 按 WC 根缓存 `svn status --xml` 结果，避免 Finder 刷角标时频繁打进程。
actor FinderSyncStatusCache {
    private var roots: [String] = []
    private var mode: FinderSyncCacheMode = .defaultCache
    private var overlaySettings = FinderSyncOverlaySettings()
    private var cache: [String: (date: Date, statuses: [FileStatus])] = [:]
    private var inFlight: [String: Task<[FileStatus], Never>] = [:]
    private var configurationGeneration = 0

    func updateConfiguration(_ configuration: FinderSyncRootsFile) {
        let normalizedRoots = configuration.roots.map { ($0 as NSString).standardizingPath }
        guard roots != normalizedRoots
                || mode != configuration.cacheMode
                || overlaySettings != configuration.overlaySettings else { return }
        configurationGeneration += 1
        roots = normalizedRoots
        mode = configuration.cacheMode
        overlaySettings = configuration.overlaySettings
        cache.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }

    func collectsBadges() -> Bool {
        FinderSyncCachePolicy(mode: mode).collectsBadges
    }

    fileprivate func requestContext(containing path: String) -> FinderSyncRequestContext? {
        let normalized = (path as NSString).standardizingPath
        guard overlaySettings.allows(path: normalized) else { return nil }
        let matchingRoots = roots
            .filter { normalized == $0 || normalized.hasPrefix($0 + "/") }
        guard let root = matchingRoots.max(by: { $0.count < $1.count }) else { return nil }
        return FinderSyncRequestContext(root: root, overlaySettings: overlaySettings)
    }

    func cachedStatuses(for key: String, ttl: TimeInterval) -> [FileStatus]? {
        guard let entry = cache[key], Date().timeIntervalSince(entry.date) < ttl else {
            return nil
        }
        return entry.statuses
    }

    func statuses(for root: String, requestedTarget: String) async -> [FileStatus]? {
        let policy = FinderSyncCachePolicy(mode: mode)
        guard policy.collectsBadges,
              let scope = policy.statusScope(requestedTarget: requestedTarget) else {
            return nil
        }
        let generation = configurationGeneration
        let normalizedRoot = (root as NSString).standardizingPath
        let key = normalizedRoot + "\u{0}" + scope + "\u{0}" + String(generation)
        if let cached = cachedStatuses(for: key, ttl: policy.cacheTTL) {
            return cached
        }
        if let task = inFlight[key] {
            return await task.value
        }
        let task = Task {
            await Self.runSvnStatus(
                wc: URL(fileURLWithPath: normalizedRoot, isDirectory: true),
                requestedTarget: scope
            )
        }
        inFlight[key] = task
        let loaded = await task.value
        guard generation == configurationGeneration else {
            inFlight[key] = nil
            return nil
        }
        cache[key] = (Date(), loaded)
        inFlight[key] = nil
        return loaded
    }

    private static func runSvnStatus(wc: URL, requestedTarget: String) async -> [FileStatus] {
        guard let statusData = await runSvn(
            arguments: [
                "status", "--xml", "--verbose", "--no-ignore", "--non-interactive",
                requestedTarget
            ],
            wc: wc
        ), let statuses = try? StatusXMLParser.parse(statusData) else {
            return []
        }

        async let infoData = runSvn(
            arguments: ["info", "--xml", "--recursive", "--non-interactive", requestedTarget],
            wc: wc
        )
        async let currentPropertyData = runSvn(
            arguments: [
                "proplist", "--xml", "--verbose", "--recursive", "--non-interactive",
                requestedTarget
            ],
            wc: wc
        )
        async let basePropertyData = runSvn(
            arguments: [
                "proplist", "--xml", "--verbose", "--recursive",
                "--revision", "BASE", "--non-interactive", requestedTarget
            ],
            wc: wc
        )
        let (loadedInfoData, loadedCurrentPropertyData, loadedBasePropertyData) = await (
            infoData,
            currentPropertyData,
            basePropertyData
        )

        let depths = loadedInfoData.flatMap { try? FinderSyncInfoXMLParser.parseDepths($0) } ?? [:]
        let currentProperties = loadedCurrentPropertyData.flatMap { try? PropertyXMLParser.parse($0) } ?? []
        let baseProperties = loadedBasePropertyData.flatMap { try? PropertyXMLParser.parse($0) }
        let pathMetadata = statuses.map { status in
            let url = status.path == "." ? wc : wc.appendingPathComponent(status.path)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            let nestedMetadata = url.appendingPathComponent(".svn", isDirectory: true)
            return FinderSyncPathMetadata(
                path: status.path,
                isReadOnly: exists && !FileManager.default.isWritableFile(atPath: url.path),
                depth: depths[status.path],
                isNestedWorkingCopy: status.path != "."
                    && isDirectory.boolValue
                    && FileManager.default.fileExists(atPath: nestedMetadata.path)
            )
        }
        return FinderSyncStatusEnricher.enrich(
            statuses: statuses,
            currentProperties: currentProperties,
            baseProperties: baseProperties,
            pathMetadata: pathMetadata
        )
    }

    private static func runSvn(arguments: [String], wc: URL) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["svn"] + arguments
                process.currentDirectoryURL = wc
                process.environment = ProcessInfo.processInfo.environment.merging([
                    "LC_ALL": "C",
                    "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:"
                        + (ProcessInfo.processInfo.environment["PATH"] ?? ""),
                ]) { _, new in new }

                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0 ? data : nil)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
