import SwiftUI
import MacSvnCore

/// 锁定工作区：获取锁 / 释放锁 / 打断锁（#19–#21），支持 CFM/⌘K 深链。
public struct MacSvnLocksView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession

    @State private var paths: [String] = []
    @State private var selected: Set<String> = []
    @State private var viewModel: LockViewModel?
    @State private var message = ""
    @State private var stealLock = false
    @State private var statusText: String?
    @State private var showGetLockSheet = false
    @State private var confirmSteal = false
    @State private var confirmBreak = false
    @State private var pendingConfirmPaths: [String] = []
    @State private var lockIntentTask: Task<Void, Never>?

    public init(
        workspaceController: MacSvnWorkspaceController,
        session: MacSvnAppSession,
        navigator: MacSvnAppNavigator
    ) {
        self.workspaceController = workspaceController
        self.session = session
        self.navigator = navigator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("锁定")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Button("刷新") { Task { await reload() } }
                Button("获取锁…") {
                    stealLock = false
                    showGetLockSheet = true
                }
                .disabled(selected.isEmpty || isBusy)
                Button("释放锁") {
                    Task { await runRelease() }
                }
                .disabled(selected.isEmpty || isBusy)
                Button("打断锁…", role: .destructive) {
                    pendingConfirmPaths = LockActionPolicy.pathsEligibleForBreak(
                        selected: Array(selected),
                        locks: viewModel?.locks ?? []
                    )
                    confirmBreak = true
                }
                .disabled(selected.isEmpty || isBusy)
            }
            .padding(24)

            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }

            if workspaceController.selectedRecord == nil {
                ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
            } else {
                HSplitView {
                    MacSvnPathPicker(paths: paths, selection: $selected)
                        .frame(minWidth: 220)
                    List(viewModel?.locks ?? [], id: \.target) { lock in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(lock.target).font(.headline)
                                Spacer()
                                Text(lockBadge(lock))
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(lockBadgeColor(lock).opacity(0.15))
                                    .foregroundStyle(lockBadgeColor(lock))
                                    .clipShape(Capsule())
                            }
                            Text("所有者：\(lock.owner ?? "-")")
                                .font(.caption)
                            if let comment = lock.comment, !comment.isEmpty {
                                Text(comment)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            Button("获取锁…") {
                                selected = [lock.target]
                                stealLock = false
                                showGetLockSheet = true
                            }
                            if lock.isOwnedByWorkingCopy {
                                Button("释放锁") {
                                    selected = [lock.target]
                                    Task { await runRelease() }
                                }
                            }
                            if lock.isRepositoryLocked {
                                Button("打断锁…", role: .destructive) {
                                    selected = [lock.target]
                                    pendingConfirmPaths = [lock.target]
                                    confirmBreak = true
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            await bootstrap()
            enqueueConsumePendingLockIntent()
        }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await bootstrap() }
        }
        .onChange(of: navigator.pendingLockIntent) { _, _ in
            enqueueConsumePendingLockIntent()
        }
        .sheet(isPresented: $showGetLockSheet) {
            getLockSheet
        }
        .confirmationDialog(
            "确认夺锁（svn lock --force）？将强制获取他人已持有的锁。",
            isPresented: $confirmSteal,
            titleVisibility: .visible
        ) {
            Button("夺锁", role: .destructive) {
                Task {
                    await viewModel?.lock(
                        paths: pendingConfirmPaths,
                        message: message,
                        force: true,
                        confirmed: true
                    )
                    await syncStatus()
                }
            }
            Button("取消", role: .cancel) {
                viewModel?.cancelConfirmation()
            }
        }
        .confirmationDialog(
            "确认打断锁（svn unlock --force）？此操作会强制解除他人锁，不可轻易撤销。",
            isPresented: $confirmBreak,
            titleVisibility: .visible
        ) {
            Button("打断锁", role: .destructive) {
                Task {
                    await viewModel?.breakLock(paths: pendingConfirmPaths, confirmed: true)
                    await syncStatus()
                }
            }
            Button("取消", role: .cancel) {
                viewModel?.cancelConfirmation()
            }
        }
    }

    private var isBusy: Bool {
        switch viewModel?.state {
        case .loading, .locking, .unlocking:
            return true
        default:
            return false
        }
    }

    private var getLockSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("获取锁")
                .font(.headline)
            Text("将对 \(selected.count) 个路径执行 svn lock。")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("锁定注释（可选）", text: $message)
                .textFieldStyle(.roundedBorder)
            Toggle("夺锁（--force，若已被他人锁定）", isOn: $stealLock)
            HStack {
                Button("取消") { showGetLockSheet = false }
                Spacer()
                Button("获取锁") {
                    showGetLockSheet = false
                    Task { await runGetLock() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func bootstrap() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            paths = []
            viewModel = nil
            return
        }
        let wc = URL(fileURLWithPath: record.localPath)
        paths = await MacSvnPathLoader.loadPaths(svnService: session.svnService, wc: wc)
        viewModel = LockViewModel(workingCopy: wc, provider: session.svnService)
        await reload()
    }

    private func reload() async {
        // 无选中时扫描整个 WC（targets 空 → status 根）
        let targets = selected.isEmpty ? [] : Array(selected).sorted()
        await viewModel?.load(targets: targets)
        await syncStatus()
    }

    private func syncStatus() async {
        guard let viewModel else {
            statusText = nil
            return
        }
        if case .error(let message) = viewModel.state {
            statusText = message
        } else if case .confirmationRequired(let op, let paths) = viewModel.state {
            pendingConfirmPaths = paths
            switch op {
            case .stealLock:
                confirmSteal = true
                statusText = "等待确认夺锁：\(paths.count) 项"
            case .breakLock:
                confirmBreak = true
                statusText = "等待确认打断锁：\(paths.count) 项"
            default:
                statusText = "等待确认"
            }
        } else {
            statusText = "锁记录 \(viewModel.locks.count)"
        }
    }

    private func runGetLock() async {
        let paths = Array(selected).sorted()
        if stealLock {
            pendingConfirmPaths = paths
            confirmSteal = true
            return
        }
        await viewModel?.lock(paths: paths, message: message, force: false, confirmed: true)
        await syncStatus()
    }

    private func runRelease() async {
        let paths = LockActionPolicy.pathsEligibleForRelease(
            selected: Array(selected),
            locks: viewModel?.locks ?? []
        )
        guard !paths.isEmpty else {
            statusText = "选中路径中没有本工作副本持有的锁"
            return
        }
        await viewModel?.unlock(paths: paths, force: false, confirmed: true)
        await syncStatus()
    }

    private func enqueueConsumePendingLockIntent() {
        lockIntentTask?.cancel()
        lockIntentTask = Task {
            await consumePendingLockIntent()
        }
    }

    private func consumePendingLockIntent() async {
        guard navigator.pendingLockIntent != nil else { return }
        let intent = navigator.consumePendingLockIntent()
        let pendingPaths = navigator.consumePendingLockPaths()
        guard let intent else { return }
        guard !Task.isCancelled else { return }

        guard !pendingPaths.isEmpty else {
            statusText = "请先在变更区选中路径后再执行锁定命令（⌘K 需带路径或从 CFM 右键进入）"
            return
        }

        selected = Set(pendingPaths)
        statusText = "来自变更区：\(intentLabel(intent))"
        await reload()
        guard !Task.isCancelled else { return }

        switch intent {
        case .getLock:
            stealLock = false
            showGetLockSheet = true
        case .releaseLock:
            await runRelease()
        case .breakLock:
            pendingConfirmPaths = LockActionPolicy.pathsEligibleForBreak(
                selected: Array(selected),
                locks: viewModel?.locks ?? []
            )
            if pendingConfirmPaths.isEmpty {
                statusText = "选中路径中没有可打断的仓库锁"
            } else {
                confirmBreak = true
            }
        }
    }

    private func intentLabel(_ intent: LockActionIntent) -> String {
        switch intent {
        case .getLock: return "获取锁"
        case .releaseLock: return "释放锁"
        case .breakLock: return "打断锁"
        }
    }

    private func lockBadge(_ lock: SvnLock) -> String {
        if lock.isOwnedByWorkingCopy {
            return "本 WC"
        }
        if lock.isRepositoryLocked {
            return "他人"
        }
        return "锁"
    }

    private func lockBadgeColor(_ lock: SvnLock) -> Color {
        if lock.isOwnedByWorkingCopy {
            return .green
        }
        if lock.isRepositoryLocked {
            return .orange
        }
        return .secondary
    }
}
