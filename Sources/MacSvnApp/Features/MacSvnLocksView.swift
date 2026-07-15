import SwiftUI
import MacSvnCore

/// 锁定工作区：获取锁 / 释放锁 / 打断锁（#19–#21），支持 CFM/⌘K 深链。
public struct MacSvnLocksView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession

    @State private var paths: [String] = []
    @State private var selected: Set<String> = []
    @State private var searchText = ""
    @State private var selectedLockTarget: String?
    @State private var viewModel: LockViewModel?
    @State private var message = ""
    @State private var automaticTemplateMessage: String?
    @State private var stealLock = false
    @State private var statusText: LocalizedStringKey?
    @State private var showGetLockSheet = false
    @State private var confirmSteal = false
    @State private var confirmBreak = false
    @State private var pendingConfirmPaths: [String] = []
    @State private var isApplyingLockIntent = false
    @State private var lockIntentTask: Task<Void, Never>?
    @State private var targetRefreshTask: Task<Void, Never>?

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
            locksToolbar
            locksFeedback

            if workspaceController.selectedRecord == nil {
                ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                locksWorkspace
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .onChange(of: selected) { _, _ in
            guard !isApplyingLockIntent else { return }
            enqueueTargetRefresh()
        }
        .sheet(isPresented: $showGetLockSheet) {
            getLockSheet
                .macSvnDismissibleSheet()
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

    private var locksToolbar: some View {
        HStack(spacing: 8) {
            Label("锁定", systemImage: "lock")
                .font(.headline)
            Text(selected.isEmpty ? "全部目标" : "已选 \(selected.count) 项")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("刷新锁记录")
            .accessibilityLabel("刷新锁记录")
            .disabled(isBusy)

            Button("获取锁", systemImage: "lock.fill") {
                requestGetLock()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty || isBusy)

            Menu {
                Button("释放锁", systemImage: "lock.open") {
                    Task { await runRelease() }
                }
                .disabled(eligibleReleasePaths.isEmpty || isBusy)
                Divider()
                Button("打断锁…", systemImage: "lock.slash", role: .destructive) {
                    pendingConfirmPaths = eligibleBreakPaths
                    confirmBreak = true
                }
                .disabled(eligibleBreakPaths.isEmpty || isBusy)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 28, height: 28)
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .help("更多锁操作")
            .accessibilityLabel("更多锁操作")
        }
        .padding(.horizontal, 16)
        .frame(height: MacSvnAuxiliaryWorkflowMetrics.toolbarHeight)
        .background(.bar)
    }

    private var locksFeedback: some View {
        HStack(spacing: 6) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在刷新锁记录")
            } else if let statusText {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(statusText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: MacSvnAuxiliaryWorkflowMetrics.feedbackHeight)
        .background(Color.secondary.opacity(0.04))
    }

    private var locksWorkspace: some View {
        HStack(spacing: 0) {
            locksMasterPane
                .frame(width: MacSvnAuxiliaryWorkflowMetrics.masterWidth)
            Divider()
            lockDetailPane
                .frame(
                    minWidth: MacSvnAuxiliaryWorkflowMetrics.detailMinimumWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
        }
    }

    private var locksMasterPane: some View {
        MacSvnAuxiliaryPathList(
            paths: paths,
            selection: $selected,
            searchText: $searchText
        )
        .disabled(isBusy)
    }

    private var lockDetailPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("锁记录")
                    .font(.headline)
                Spacer()
                Text("\(viewModel?.locks.count ?? 0)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)

            Divider()

            if viewModel?.locks.isEmpty != false {
                ContentUnavailableView("没有锁记录",
                    systemImage: "lock.open",
                    description: Text(selected.isEmpty ? "当前工作副本没有锁记录" : "所选目标没有锁记录")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedLockTarget) {
                    ForEach(viewModel?.locks ?? [], id: \.target) { lock in
                        lockRow(lock)
                            .tag(lock.target)
                            .contextMenu { lockContextMenu(lock) }
                    }
                }
                .listStyle(.inset)

                if let selectedLock {
                    Divider()
                    lockInspector(selectedLock)
                }
            }
        }
    }

    private func lockRow(_ lock: SvnLock) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(MacSvnAuxiliaryPathPresentation.title(for: lock.target))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(lock.target)
                Spacer()
                Label(lockBadge(lock), systemImage: lockBadgeSystemImage(lock))
                    .labelStyle(.titleAndIcon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(lockBadgeColor(lock))
            }
            HStack(spacing: 10) {
                Text(lock.owner ?? "未知所有者")
                if let created = lock.created {
                    Text(created.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let comment = lock.comment, !comment.isEmpty {
                Text(comment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(comment)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func lockContextMenu(_ lock: SvnLock) -> some View {
        Button("获取锁…") {
            selected = [lock.target]
            requestGetLock()
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

    private func lockInspector(_ lock: SvnLock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(lockBadge(lock), systemImage: lockBadgeSystemImage(lock))
                    .font(.headline)
                    .foregroundStyle(lockBadgeColor(lock))
                Spacer()
            }
            LabeledContent("路径") {
                Text(lock.target)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(lock.target)
            }
            LabeledContent("所有者", value: lock.owner ?? "未知")
            LabeledContent(
                "创建时间",
                value: lock.created?.formatted(date: .abbreviated, time: .shortened) ?? "未知"
            )
            if let comment = lock.comment, !comment.isEmpty {
                LabeledContent("注释") {
                    Text(comment)
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .help(comment)
                }
            }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedLock: SvnLock? {
        guard let selectedLockTarget else { return nil }
        return viewModel?.locks.first { $0.target == selectedLockTarget }
    }

    private var eligibleReleasePaths: [String] {
        MacSvnLockActionPresentation.eligibleReleasePaths(
            selected: Array(selected),
            locks: viewModel?.locks ?? []
        )
    }

    private var eligibleBreakPaths: [String] {
        LockActionPolicy.pathsEligibleForBreak(
            selected: Array(selected),
            locks: viewModel?.locks ?? []
        )
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
            if let loadError = viewModel?.projectPropertyLoadError {
                Text("项目属性读取失败，已阻止获取锁：\(loadError)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let minimum = viewModel?.projectProperties.lock.minimumMessageLength {
                Text("最少 \(minimum) 个字符")
                    .font(.caption)
                    .foregroundStyle(lockMessageIsLongEnough ? Color.secondary : Color.red)
            }
            Toggle("夺锁（--force，若已被他人锁定）", isOn: $stealLock)
            HStack {
                Button("取消") { showGetLockSheet = false }
                Spacer()
                Button("获取锁") {
                    showGetLockSheet = false
                    Task { await runGetLock() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!lockMessageIsLongEnough || viewModel?.projectPropertyLoadError != nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var lockMessageIsLongEnough: Bool {
        guard let projectProperties = viewModel?.projectProperties else { return true }
        return LockMessagePolicy.validationError(for: message, properties: projectProperties) == nil
    }

    private func bootstrap() async {
        targetRefreshTask?.cancel()
        viewModel = nil
        selected = []
        selectedLockTarget = nil
        searchText = ""
        guard let record = workspaceController.selectedRecord, record.isValid else {
            paths = []
            return
        }
        let wc = URL(fileURLWithPath: record.localPath)
        paths = await MacSvnPathLoader.loadPaths(svnService: session.svnService, wc: wc)
        do {
            let projectProperties = try await MacSvnProjectPropertyLoader.load(
                svnService: session.svnService,
                workingCopy: wc,
                relativePaths: selected.isEmpty ? paths : Array(selected)
            )
            applyLockTemplate(projectProperties.lock.initialMessage)
            viewModel = LockViewModel(
                workingCopy: wc,
                provider: session.svnService,
                projectPropertyLoader: { [svnService = session.svnService] paths in
                    try await MacSvnProjectPropertyLoader.load(
                        svnService: svnService,
                        workingCopy: wc,
                        relativePaths: paths
                    )
                },
                projectProperties: projectProperties
            )
            await reload()
        } catch {
            viewModel = nil
            statusText = "项目属性读取失败：\(error.localizedDescription)"
        }
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
            selectedLockTarget = nil
            return
        }
        let lockTargets = Set(viewModel.locks.map(\.target))
        if selectedLockTarget == nil || !lockTargets.contains(selectedLockTarget ?? "") {
            selectedLockTarget = viewModel.locks.first?.target
        }
        if case .error(let message) = viewModel.state {
            statusText = LocalizedStringKey(message)
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
            statusText = viewModel.locks.isEmpty
                ? "没有锁记录"
                : "锁记录 \(viewModel.locks.count)"
        }
    }

    private func runGetLock() async {
        guard viewModel?.projectPropertyLoadError == nil else {
            statusText = "项目属性读取失败，无法获取锁"
            return
        }
        let paths = Array(selected).sorted()
        if stealLock {
            pendingConfirmPaths = paths
            confirmSteal = true
            return
        }
        await viewModel?.lock(paths: paths, message: message, force: false, confirmed: true)
        await syncStatus()
    }

    private func requestGetLock() {
        stealLock = false
        let requiresMessage = viewModel?.projectProperties.lock.minimumMessageLength != nil
            || viewModel?.projectProperties.lock.initialMessage?.isEmpty == false
        let containsDirectory: Bool
        if let record = workspaceController.selectedRecord {
            let workingCopy = URL(fileURLWithPath: record.localPath)
            containsDirectory = selected.contains { path in
                var isDirectory: ObjCBool = false
                let fullPath = workingCopy.appendingPathComponent(path).path
                return FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
        } else {
            containsDirectory = false
        }
        if session.settingsSnapshot.dialogs.showLockDialogBeforeLocking
            || requiresMessage
            || containsDirectory {
            showGetLockSheet = true
        } else {
            message = ""
            Task { await runGetLock() }
        }
    }

    private func runRelease() async {
        let paths = eligibleReleasePaths
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

    private func enqueueTargetRefresh() {
        guard let viewModel else { return }
        targetRefreshTask?.cancel()
        let selectionSnapshot = selected
        let projectPropertyTargets = selectionSnapshot.isEmpty
            ? paths
            : Array(selectionSnapshot).sorted()
        let lockTargets = selectionSnapshot.isEmpty
            ? []
            : Array(selectionSnapshot).sorted()
        targetRefreshTask = Task {
            await viewModel.refreshProjectProperties(for: projectPropertyTargets)
            guard !Task.isCancelled, selectionSnapshot == selected else { return }
            applyLockTemplate(viewModel.projectProperties.lock.initialMessage)
            await viewModel.load(targets: lockTargets)
            guard !Task.isCancelled, selectionSnapshot == selected else { return }
            await syncStatus()
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

        targetRefreshTask?.cancel()
        isApplyingLockIntent = true
        defer { isApplyingLockIntent = false }
        selected = Set(pendingPaths)
        statusText = "来自变更区：\(intentLabel(intent))"
        await reload()
        guard !Task.isCancelled else { return }

        switch intent {
        case .getLock:
            requestGetLock()
        case .releaseLock:
            await runRelease()
        case .breakLock:
            pendingConfirmPaths = eligibleBreakPaths
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

    private func applyLockTemplate(_ template: String?) {
        guard message.isEmpty || message == automaticTemplateMessage else { return }
        automaticTemplateMessage = template
        message = template ?? ""
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

    private func lockBadgeSystemImage(_ lock: SvnLock) -> String {
        lock.isOwnedByWorkingCopy ? "lock.fill" : "lock"
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
