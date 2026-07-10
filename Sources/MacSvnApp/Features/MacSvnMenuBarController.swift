import Foundation
import MacSvnCore
import UserNotifications

/// 菜单栏状态：远端轮询 + 本地 FSEvents 近实时刷新（FR-EX-03）。
@MainActor
public final class MacSvnMenuBarController: ObservableObject {
    @Published public private(set) var snapshot: MenuBarStatusSnapshot?
    @Published public private(set) var lastError: String?
    @Published public var isPollingEnabled = true
    /// 测试可观测：本地 FS 变更触发的刷新次数。
    @Published public private(set) var localRefreshTriggerCount = 0

    private let workspaceStore: WorkspaceStore
    private let snapshotter: MenuBarStatusSnapshotter
    private let pollIntervalSeconds: TimeInterval
    private let changeWatcher: (any WorkingCopyChangeWatching)?
    private let localRefreshDebounceNanoseconds: UInt64
    private let requestsNotificationPermission: Bool
    private var pollTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var lastNotifiedKeys: Set<String> = []

    public init(
        workspaceStore: WorkspaceStore,
        snapshotter: MenuBarStatusSnapshotter,
        pollIntervalMinutes: Int = 10,
        changeWatcher: (any WorkingCopyChangeWatching)? = FSEventsWorkingCopyWatcher(),
        localRefreshDebounceNanoseconds: UInt64 = 400_000_000,
        requestsNotificationPermission: Bool = true
    ) {
        self.workspaceStore = workspaceStore
        self.snapshotter = snapshotter
        self.pollIntervalSeconds = TimeInterval(max(1, pollIntervalMinutes) * 60)
        self.changeWatcher = changeWatcher
        self.localRefreshDebounceNanoseconds = localRefreshDebounceNanoseconds
        self.requestsNotificationPermission = requestsNotificationPermission
    }

    public func start() {
        guard pollTask == nil else { return }
        if requestsNotificationPermission {
            Self.requestNotificationPermission()
        }
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                if self.isPollingEnabled {
                    await self.refresh(reason: .poll)
                }
                try? await Task.sleep(nanoseconds: UInt64(self.pollIntervalSeconds * 1_000_000_000))
            }
        }
        // 首次 poll 的 refresh 会 rearmLocalWatcher；此处不再单独 rearm，避免重复 startWatching。
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        changeWatcher?.stopWatching()
    }

    public func refresh() async {
        await refresh(reason: .manual)
    }

    public func refresh(reason: RefreshReason) async {
        do {
            let records = try await workspaceStore.load()
            let next = try await snapshotter.snapshot(records: records)
            snapshot = next
            lastError = nil
            postNotificationsIfNeeded(next)
            if reason == .localFSEvent {
                localRefreshTriggerCount += 1
            }
            if reason != .localFSEvent {
                await rearmLocalWatcher(with: records)
            }
        } catch {
            lastError = String(describing: error)
        }
    }

    /// 供测试/内部：模拟一次本地 FS 变更回调。
    public func handleLocalFileSystemChangeForTesting() {
        scheduleLocalRefresh()
    }

    public var badgeText: String {
        guard let snapshot else { return "SVN" }
        let local = snapshot.totalLocalChangeCount
        let remote = snapshot.totalRemoteNewCommitCount
        if local == 0, remote == 0 { return "SVN" }
        return "\(local)/\(remote)"
    }

    public enum RefreshReason: Equatable, Sendable {
        case poll
        case manual
        case localFSEvent
    }

    private func rearmLocalWatcher(with records: [WorkingCopyRecord]? = nil) async {
        guard let changeWatcher else { return }
        let loaded: [WorkingCopyRecord]
        if let records {
            loaded = records
        } else {
            loaded = (try? await workspaceStore.load()) ?? []
        }
        let paths = loaded.filter(\.isValid).map(\.localPath)
        changeWatcher.stopWatching()
        changeWatcher.startWatching(paths: paths) { [weak self] in
            Task { @MainActor in
                self?.scheduleLocalRefresh()
            }
        }
    }

    private func scheduleLocalRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.localRefreshDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self.refresh(reason: .localFSEvent)
        }
    }

    /// 通知授权回调跑在系统后台队列。若在 `@MainActor` 方法内写闭包，Swift 6 会把闭包标成 MainActor，
    /// 回调时触发 `dispatch_assert_queue` → `EXC_BAD_INSTRUCTION`（本机崩溃报告已证实）。
    nonisolated private static func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            // 仅申请权限，不触碰 MainActor 状态
        }
    }

    private func postNotificationsIfNeeded(_ snapshot: MenuBarStatusSnapshot) {
        for item in snapshot.workingCopies {
            guard let summary = item.notificationSummary,
                  item.remoteNewCommitCount > 0
            else { continue }

            let key = "\(item.recordID.uuidString)-\(item.remoteLatestRevision?.value ?? 0)"
            guard !lastNotifiedKeys.contains(key) else { continue }
            lastNotifiedKeys.insert(key)

            let content = UNMutableNotificationContent()
            content.title = ProductBranding.displayName
            content.body = summary
            let request = UNNotificationRequest(
                identifier: key,
                content: content,
                trigger: nil
            )
            // completionHandler 必须为 nil 或 nonisolated；勿在此写 MainActor 闭包
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }
}
