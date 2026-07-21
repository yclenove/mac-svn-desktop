import SwiftUI
import MacSvnCore

struct GetLockDraftSnapshot: Equatable {
    let message: String
    let stealLock: Bool
}

/// 锁定工作区：获取锁 / 释放锁 / 打断锁（#19–#21），支持 CFM/⌘K 深链。
public struct MacSvnLocksView: View {
    @Environment(\.locale) private var locale
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
    @State private var feedback: MacSvnAuxiliaryFeedback?
    @State private var showGetLockSheet = false
    @State private var getLockInitialDraft: GetLockDraftSnapshot?
    @State private var showDiscardGetLockConfirmation = false
    @State private var confirmSteal = false
    @State private var confirmBreak = false
    @State private var pendingConfirmPaths: [String] = []
    @State private var isApplyingLockIntent = false
    @State private var lockIntentTask: Task<Void, Never>?
    @State private var targetRefreshTask: Task<Void, Never>?
    @State private var isRefreshingTargets = false
    @State private var targetRefreshGeneration = 0
    @FocusState private var isSearchFocused: Bool

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
        .background {
            Button("") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
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
        .onChange(of: selected) { _, _ in
            guard !isApplyingLockIntent else { return }
            enqueueTargetRefresh()
        }
        .sheet(isPresented: $showGetLockSheet) {
            getLockSheet
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
                            completeGetLockSubmission()
                        }
                    }
                    .disabled(isBusy)
                    Button("取消", role: .cancel) {
                        viewModel?.cancelConfirmation()
                    }
                }
                .confirmationDialog(
                    "放弃未保存更改？",
                    isPresented: $showDiscardGetLockConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("放弃更改", role: .destructive) { discardGetLockChanges() }
                    Button("继续编辑", role: .cancel) {}
                }
                .macSvnDismissibleSheet(
                    preventsDismissal: getLockPreventsDismissal,
                    onDismissalBlocked: requestGetLockDismissal
                )
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
                requestTargetRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("刷新锁记录")
            .accessibilityLabel("刷新锁记录")
            .accessibilityIdentifier("macSvn.locks.refresh")
            .keyboardShortcut("r", modifiers: .command)
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
        MacSvnInlineFeedbackView(
            feedback: currentLocksFeedback,
            truncationMode: .middle
        )
    }

    private var currentLocksFeedback: MacSvnAuxiliaryFeedback? {
        MacSvnLockFeedbackPresentation.feedback(
            state: viewModel?.state,
            projectPropertyLoadError: viewModel?.projectPropertyLoadError,
            projectPropertyLoadDiagnostic: viewModel?.projectPropertyLoadDiagnostic,
            lockCount: viewModel?.locks.count ?? 0,
            fallback: feedback,
            locale: locale
        )
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
            searchText: $searchText,
            searchFocus: $isSearchFocused,
            searchAccessibilityIdentifier: "macSvn.locks.search"
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
        if isRefreshingTargets { return true }
        switch viewModel?.state {
        case .loading, .locking, .unlocking:
            return true
        default:
            return false
        }
    }

    private var currentGetLockDraft: GetLockDraftSnapshot {
        GetLockDraftSnapshot(message: message, stealLock: stealLock)
    }

    private var hasUnsavedGetLockChanges: Bool {
        guard let getLockInitialDraft else { return false }
        return currentGetLockDraft != getLockInitialDraft
    }

    private var getLockDismissalDecision: MacSvnAuxiliaryDismissalDecision {
        MacSvnAuxiliaryDismissalPolicy.decision(
            isBusy: isBusy,
            isDirty: hasUnsavedGetLockChanges
        )
    }

    private var getLockPreventsDismissal: Bool {
        getLockDismissalDecision.preventsDismissal
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
            if let loadError = viewModel?.projectPropertyLoadError,
               let loadFeedback = MacSvnLockFeedbackPresentation.feedback(
                    state: .loaded,
                    projectPropertyLoadError: loadError,
                    projectPropertyLoadDiagnostic: viewModel?.projectPropertyLoadDiagnostic,
                    lockCount: viewModel?.locks.count ?? 0,
                    fallback: nil,
                    locale: locale
               ) {
                MacSvnInlineFeedbackView(feedback: loadFeedback)
            }
            if let minimum = viewModel?.projectProperties.lock.minimumMessageLength {
                Text("最少 \(minimum) 个字符")
                    .font(.caption)
                    .foregroundStyle(lockMessageIsLongEnough ? Color.secondary : Color.red)
            }
            Toggle("夺锁（--force，若已被他人锁定）", isOn: $stealLock)
                .disabled(isBusy)
            HStack {
                Button("取消") { requestGetLockDismissal() }
                    .disabled(isBusy)
                Spacer()
                Button("获取锁") {
                    Task { await runGetLock() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    !lockMessageIsLongEnough
                        || viewModel?.projectPropertyLoadError != nil
                        || isBusy
                )
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
            let diagnostic = error.localizedDescription
            let presented = MacSvnAuxiliaryErrorSummaryPresentation.message(diagnostic, locale: locale)
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .failure,
                message: "项目属性读取失败：\(presented)",
                locale: locale,
                diagnostic: diagnostic
            )
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
            feedback = nil
            selectedLockTarget = nil
            return
        }
        let lockTargets = Set(viewModel.locks.map(\.target))
        if selectedLockTarget == nil || !lockTargets.contains(selectedLockTarget ?? "") {
            selectedLockTarget = viewModel.locks.first?.target
        }
        if case .confirmationRequired(let op, let paths) = viewModel.state {
            pendingConfirmPaths = paths
            switch op {
            case .stealLock:
                confirmSteal = true
            case .breakLock:
                confirmBreak = true
            default: break
            }
        }
        feedback = MacSvnLockFeedbackPresentation.feedback(
            state: viewModel.state,
            projectPropertyLoadError: viewModel.projectPropertyLoadError,
            projectPropertyLoadDiagnostic: viewModel.projectPropertyLoadDiagnostic,
            lockCount: viewModel.locks.count,
            fallback: feedback,
            locale: locale
        )
    }

    private func runGetLock() async {
        guard viewModel?.projectPropertyLoadError == nil else {
            feedback = MacSvnLockFeedbackPresentation.feedback(
                state: .loaded,
                projectPropertyLoadError: viewModel?.projectPropertyLoadError,
                projectPropertyLoadDiagnostic: viewModel?.projectPropertyLoadDiagnostic,
                lockCount: viewModel?.locks.count ?? 0,
                fallback: feedback,
                locale: locale
            )
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
        completeGetLockSubmission()
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
        if MacSvnGetLockPresentationPolicy.shouldPresent(
            userPreference: session.settingsSnapshot.dialogs.showLockDialogBeforeLocking,
            requiresMessage: requiresMessage,
            containsDirectory: containsDirectory
        ) {
            getLockInitialDraft = currentGetLockDraft
            showGetLockSheet = true
        } else {
            message = ""
            Task { await runGetLock() }
        }
    }

    private func runRelease() async {
        let paths = eligibleReleasePaths
        guard !paths.isEmpty else {
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .warning,
                message: "选中路径中没有本工作副本持有的锁",
                locale: locale,
                diagnostic: nil
            )
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

    private func requestTargetRefresh() {
        guard !isRefreshingTargets else { return }
        guard !isBusy else { return }
        guard viewModel != nil else { return }
        enqueueTargetRefresh()
    }

    private func enqueueTargetRefresh() {
        guard let viewModel else { return }
        targetRefreshTask?.cancel()
        targetRefreshGeneration += 1
        let refreshGeneration = targetRefreshGeneration
        isRefreshingTargets = true
        let selectionSnapshot = selected
        let projectPropertyTargets = selectionSnapshot.isEmpty
            ? paths
            : Array(selectionSnapshot).sorted()
        let lockTargets = selectionSnapshot.isEmpty
            ? []
            : Array(selectionSnapshot).sorted()
        targetRefreshTask = Task {
            defer {
                if refreshGeneration == targetRefreshGeneration {
                    isRefreshingTargets = false
                }
            }
            let didApplyProjectProperties = await viewModel.refreshProjectProperties(
                for: projectPropertyTargets
            )
            guard !Task.isCancelled, selectionSnapshot == selected else { return }
            guard didApplyProjectProperties else {
                await syncStatus()
                return
            }
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
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .warning,
                message: "请先在变更区选中路径后再执行锁定命令（⌘K 需带路径或从 CFM 右键进入）",
                locale: locale,
                diagnostic: nil
            )
            return
        }

        targetRefreshTask?.cancel()
        isApplyingLockIntent = true
        defer { isApplyingLockIntent = false }
        selected = Set(pendingPaths)
        feedback = MacSvnAuxiliaryFeedback.localized(
            kind: .success,
            message: "来自变更区：\(intentLabel(intent))",
            locale: locale,
            diagnostic: nil
        )
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
                feedback = MacSvnAuxiliaryFeedback.localized(
                    kind: .warning,
                    message: "选中路径中没有可打断的仓库锁",
                    locale: locale,
                    diagnostic: nil
                )
            } else {
                confirmBreak = true
            }
        }
    }

    private func requestGetLockDismissal() {
        switch getLockDismissalDecision {
        case .blocked:
            return
        case .confirmDiscard:
            showDiscardGetLockConfirmation = true
        case .dismiss:
            closeGetLockSheet()
        }
    }

    private func discardGetLockChanges() {
        closeGetLockSheet()
    }

    private func completeGetLockSubmission() {
        guard case .loaded = viewModel?.state else { return }
        getLockInitialDraft = nil
        closeGetLockSheet()
    }

    private func closeGetLockSheet() {
        message = automaticTemplateMessage ?? ""
        stealLock = false
        getLockInitialDraft = nil
        showDiscardGetLockConfirmation = false
        showGetLockSheet = false
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
