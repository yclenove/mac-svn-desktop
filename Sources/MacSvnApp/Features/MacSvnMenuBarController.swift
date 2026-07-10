import Foundation
import MacSvnCore
import UserNotifications

/// 菜单栏状态轮询：聚合各 WC 本地变更与远端新提交，供 MenuBarExtra 展示。
@MainActor
public final class MacSvnMenuBarController: ObservableObject {
    @Published public private(set) var snapshot: MenuBarStatusSnapshot?
    @Published public private(set) var lastError: String?
    @Published public var isPollingEnabled = true

    private let workspaceStore: WorkspaceStore
    private let snapshotter: MenuBarStatusSnapshotter
    private let pollIntervalSeconds: TimeInterval
    private var pollTask: Task<Void, Never>?
    private var lastNotifiedKeys: Set<String> = []

    public init(
        workspaceStore: WorkspaceStore,
        snapshotter: MenuBarStatusSnapshotter,
        pollIntervalMinutes: Int = 10
    ) {
        self.workspaceStore = workspaceStore
        self.snapshotter = snapshotter
        self.pollIntervalSeconds = TimeInterval(max(1, pollIntervalMinutes) * 60)
    }

    public func start() {
        guard pollTask == nil else { return }
        requestNotificationPermission()
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                if self.isPollingEnabled {
                    await self.refresh()
                }
                try? await Task.sleep(nanoseconds: UInt64(self.pollIntervalSeconds * 1_000_000_000))
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func refresh() async {
        do {
            let records = try await workspaceStore.load()
            let next = try await snapshotter.snapshot(records: records)
            snapshot = next
            lastError = nil
            postNotificationsIfNeeded(next)
        } catch {
            lastError = String(describing: error)
        }
    }

    public var badgeText: String {
        guard let snapshot else { return "SVN" }
        let local = snapshot.totalLocalChangeCount
        let remote = snapshot.totalRemoteNewCommitCount
        if local == 0, remote == 0 { return "SVN" }
        return "\(local)/\(remote)"
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
            content.title = "MacSVN"
            content.body = summary
            let request = UNNotificationRequest(
                identifier: key,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }
}
