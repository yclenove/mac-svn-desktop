import SwiftUI
import MacSvnCore

/// 冲突工作区：列表 + 文本三路合并 / 树冲突 / 属性冲突；批量 Resolved（#12）；CFM 入口（#11）。
public struct MacSvnConflictWorkspaceView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession
    private let onReturnToChanges: (() -> Void)?

    @State private var tab: Tab = .conflicts
    @State private var listVM: ConflictListViewModel?
    @State private var editorVM: MergeEditorViewModel?
    @State private var treeVM: TreeConflictViewModel?
    @State private var propertyVM: PropertyConflictViewModel?
    @State private var statusText: LocalizedStringKey?
    @State private var conflictBadgeCount = 0
    @State private var privacySettings = AIPrivacySettings()
    @State private var kindFilterPick: KindFilterPick = .all
    @State private var confirmMarkResolved = false
    @State private var externalMergeTool: ExternalDiffToolConfiguration?
    @State private var isOpeningExternalMerge = false
    @State private var conflictReloadGeneration = 0

    private enum Tab: String, CaseIterable, Identifiable {
        case conflicts = "冲突列表"
        case mergeWizard = "合并向导"
        var id: String { rawValue }
    }

    private enum KindFilterPick: String, CaseIterable, Identifiable {
        case all = "全部"
        case text = "文本"
        case tree = "树"
        case property = "属性"
        var id: String { rawValue }
    }

    public init(
        workspaceController: MacSvnWorkspaceController,
        session: MacSvnAppSession,
        navigator: MacSvnAppNavigator,
        onReturnToChanges: (() -> Void)? = nil
    ) {
        self.workspaceController = workspaceController
        self.session = session
        self.navigator = navigator
        self.onReturnToChanges = onReturnToChanges
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            conflictToolbar
            switch tab {
            case .conflicts:
                conflictFilterBar
                if let statusText {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 24)
                }
                conflictPane
            case .mergeWizard:
                MacSvnMergeWizardView(
                    workspaceController: workspaceController,
                    session: session,
                    navigator: navigator
                )
            }
        }
        .task {
            privacySettings = await session.currentAIPrivacy()
            await reloadConflicts()
            await consumePendingConflictPath()
            if navigator.consumePendingMergeWizard() {
                tab = .mergeWizard
            }
            consumePendingResolvedHint()
        }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await reloadConflicts() }
        }
        .onChange(of: navigator.pendingConflictPath) { _, _ in
            tab = .conflicts
            Task { await consumePendingConflictPath() }
        }
        .onChange(of: navigator.pendingMergeWizard) { _, isPending in
            if isPending {
                tab = .mergeWizard
                _ = navigator.consumePendingMergeWizard()
            }
        }
        .onChange(of: navigator.pendingResolvedHint) { _, isHint in
            if isHint {
                consumePendingResolvedHint()
            }
        }
        .onChange(of: kindFilterPick) { _, pick in
            applyKindFilter(pick)
        }
        .confirmationDialog(
            "将勾选的文本/属性冲突标记为已解决（svn resolve --accept working）？树冲突请用右侧专用操作。",
            isPresented: $confirmMarkResolved,
            titleVisibility: .visible
        ) {
            Button("标记已解决") {
                Task { await markCheckedResolved() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var conflictToolbar: some View {
        HStack(spacing: 8) {
            Label("冲突", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
            if conflictBadgeCount > 0 {
                Text("\(conflictBadgeCount)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(conflictColour)
                    .accessibilityLabel("\(conflictBadgeCount) 个冲突")
            }
            Spacer(minLength: 8)
            Picker("工作区", selection: $tab) {
                ForEach(Tab.allCases) { item in
                    Text(LocalizedStringKey(item.rawValue)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            Button {
                Task { await reloadConflicts() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(listVM?.state == .loading || listVM?.state == .resolving)
            .help("刷新冲突")
            .accessibilityLabel("刷新冲突")
            .accessibilityIdentifier("macSvn.conflicts.refresh")
            .keyboardShortcut("r", modifiers: .command)
            Button {
                onReturnToChanges?()
            } label: {
                Label("返回变更", systemImage: "arrow.uturn.backward")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: MacSvnCoreModeMetrics.toolbarHeight)
    }

    @ViewBuilder
    private var conflictFilterBar: some View {
        if let listVM {
            HStack(spacing: 8) {
                Picker("类型", selection: $kindFilterPick) {
                    ForEach(KindFilterPick.allCases) { item in
                        Text(LocalizedStringKey(item.rawValue)).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                TextField(
                    "过滤路径",
                    text: Binding(
                        get: { listVM.searchText },
                        set: { listVM.searchText = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120, idealWidth: 200, maxWidth: 260)
                Text("\(listVM.visibleConflicts.count) / \(listVM.summary.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                bulkSelectionMenu
                Button {
                    confirmMarkResolved = true
                } label: {
                    Label(
                        "标记已解决 (\(listVM.checkedPathsEligibleForMarkResolved.count))",
                        systemImage: "checkmark.circle"
                    )
                }
                .disabled(
                    listVM.checkedPathsEligibleForMarkResolved.isEmpty
                        || listVM.state == .resolving
                )
                .help("对勾选的文本/属性冲突执行 svn resolve --accept working（树冲突请用右侧专用操作）")
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var bulkSelectionMenu: some View {
        if let listVM {
            Menu {
                Button("勾选可解决", systemImage: "checkmark.square") {
                    listVM.checkAllVisibleEligible()
                }
                Button("清除勾选", systemImage: "square") {
                    listVM.clearChecked()
                }
            } label: {
                Label("批量选择", systemImage: "checklist")
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("批量选择")
            .accessibilityLabel("批量选择")
        }
    }

    @ViewBuilder
    private var conflictPane: some View {
        if workspaceController.selectedRecord == nil {
            ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
        } else if let listVM {
            HStack(spacing: 0) {
                conflictList(listVM)
                    .frame(
                        minWidth: MacSvnCoreModeMetrics.masterMinimumWidth,
                        idealWidth: MacSvnCoreModeMetrics.masterIdealWidth,
                        maxWidth: MacSvnCoreModeMetrics.masterMaximumWidth
                    )
                Divider()
                detailPane
                    .frame(minWidth: MacSvnCoreModeMetrics.inspectorMinimumWidth)
            }
        } else {
            ProgressView("扫描冲突…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func conflictList(_ listVM: ConflictListViewModel) -> some View {
        List(selection: Binding(
            get: { listVM.selectedConflictPath },
            set: { path in
                guard let path else { return }
                listVM.selectConflict(path: path)
                Task { await openSelected() }
            }
        )) {
            ForEach(listVM.visibleConflicts, id: \.path) { conflict in
                HStack(spacing: 8) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { listVM.checkedPaths.contains(conflict.path) },
                            set: { listVM.setChecked(conflict.path, isChecked: $0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .disabled(!ConflictResolveBatchPolicy.isEligibleForMarkResolved(conflict))
                    .help(
                        ConflictResolveBatchPolicy.isEligibleForMarkResolved(conflict)
                            ? "勾选后可批量标记已解决"
                            : "树冲突请在右侧专用面板处理"
                    )
                    Image(systemName: kindSystemImage(conflict.kind))
                        .foregroundStyle(kindColor(conflict.kind))
                        .frame(width: 16)
                    Text(kindDisplayLabel(conflict.kind))
                        .font(.caption)
                        .foregroundStyle(kindColor(conflict.kind))
                        .frame(width: 34, alignment: .leading)
                    Text(conflict.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(conflict.path)
                }
                .tag(conflict.path)
                .contextMenu {
                    Button("编辑冲突") {
                        listVM.selectConflict(path: conflict.path)
                        Task { await openSelected() }
                    }
                    if ConflictResolveBatchPolicy.isEligibleForMarkResolved(conflict) {
                        Button("标记此项已解决") {
                            listVM.clearChecked()
                            listVM.setChecked(conflict.path, isChecked: true)
                            confirmMarkResolved = true
                        }
                    }
                }
            }
        }
        .overlay {
            switch listVM.state {
            case .idle, .loading:
                ProgressView("扫描冲突…")
            case .loaded where listVM.visibleConflicts.isEmpty:
                ContentUnavailableView("无匹配冲突", systemImage: "checkmark.seal")
            case .error(let message):
                ContentUnavailableView(
                    "加载冲突失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(
                        LocalizedStringKey(MacSvnCoreModeErrorPresentation.message(message))
                    )
                )
                .help(message)
            case .loaded, .resolving:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let conflict = listVM?.selectedConflict {
            switch conflict.kind {
            case .text:
                MacSvnMergeEditorPane(
                    conflict: conflict,
                    editorVM: editorVM,
                    privacySettings: privacySettings,
                    statusText: $statusText,
                    externalMergeTool: externalMergeTool,
                    isOpeningExternalMerge: isOpeningExternalMerge,
                    conflictColour: conflictColour
                ) {
                    Task { await reloadConflicts() }
                } onOpenExternalMerge: {
                    Task { await openExternalMerge(conflict) }
                }
            case .tree:
                MacSvnTreeConflictPane(treeVM: treeVM) {
                    Task { await reloadConflicts() }
                }
            case .property:
                MacSvnPropertyConflictPane(propertyVM: propertyVM) {
                    Task { await reloadConflicts() }
                }
            default:
                ContentUnavailableView(
                    "暂不支持的冲突类型",
                    systemImage: "exclamationmark.triangle",
                    description: Text("\(conflict.kind) — \(conflict.path)")
                )
            }
        } else {
            ContentUnavailableView("无冲突", systemImage: "checkmark.seal", description: Text("当前工作副本没有待处理冲突"))
        }
    }

    private func reloadConflicts() async {
        conflictReloadGeneration &+= 1
        let generation = conflictReloadGeneration
        guard let record = workspaceController.selectedRecord, record.isValid else {
            listVM = nil
            editorVM = nil
            treeVM = nil
            propertyVM = nil
            conflictBadgeCount = 0
            externalMergeTool = nil
            return
        }
        let wc = URL(fileURLWithPath: record.localPath)
        let list = ConflictListViewModel(
            workingCopy: wc,
            provider: session.conflictService,
            batchResolver: session.conflictService
        )
        listVM = list
        editorVM = nil
        applyKindFilter(kindFilterPick)
        await list.refresh()
        guard generation == conflictReloadGeneration,
              workspaceController.selectedID == record.id,
              listVM === list else { return }
        conflictBadgeCount = list.summary.total
        if case .error(let message) = list.state {
            statusText = LocalizedStringKey(MacSvnCoreModeErrorPresentation.message(message))
        } else {
            statusText = list.summary.total == 0 ? "无冲突" : "发现 \(list.summary.total) 个冲突"
            await openSelected()
        }
    }

    /// 仅在 listVM 就绪时消费 pending，避免路径被吞掉。
    private func consumePendingConflictPath() async {
        guard listVM != nil, navigator.pendingConflictPath != nil else { return }
        guard let path = navigator.consumePendingConflictPath(), let listVM else { return }
        listVM.selectConflict(path: path)
        statusText = "来自变更区：\(path)"
        await openSelected()
    }

    /// ⌘K「标记为已解决」：预勾选可解决项并提示确认。
    private func consumePendingResolvedHint() {
        guard navigator.consumePendingResolvedHint(), let listVM else { return }
        listVM.checkAllVisibleEligible()
        statusText = "请确认后点击「标记已解决」（已预勾选可批量项）"
        if !listVM.checkedPathsEligibleForMarkResolved.isEmpty {
            confirmMarkResolved = true
        }
    }

    private func applyKindFilter(_ pick: KindFilterPick) {
        guard let listVM else { return }
        switch pick {
        case .all:
            listVM.kindFilter = .all
        case .text:
            listVM.kindFilter = .kinds([.text])
        case .tree:
            listVM.kindFilter = .kinds([.tree])
        case .property:
            listVM.kindFilter = .kinds([.property])
        }
    }

    private func markCheckedResolved() async {
        guard let listVM else { return }
        let count = await listVM.markCheckedAsResolved()
        conflictBadgeCount = listVM.summary.total
        if case .error(let message) = listVM.state {
            statusText = LocalizedStringKey(MacSvnCoreModeErrorPresentation.message(message))
        } else if count > 0 {
            statusText = "已标记 \(count) 项为已解决"
            await openSelected()
        }
    }

    private func openSelected() async {
        guard let conflict = listVM?.selectedConflict,
              let record = workspaceController.selectedRecord
        else {
            editorVM = nil
            treeVM = nil
            propertyVM = nil
            return
        }
        let selectedPath = conflict.path
        let wc = URL(fileURLWithPath: record.localPath)
        switch conflict.kind {
        case .text:
            treeVM = nil
            propertyVM = nil
            let vm = MergeEditorViewModel(
                provider: session.conflictService,
                aiConflictAssistant: session.aiConflictAssistant
            )
            editorVM = vm
            await vm.load(conflict: conflict, wc: wc)
            guard listVM?.selectedConflictPath == selectedPath else { return }
            await refreshExternalMergeTool(for: selectedPath)
        case .tree:
            editorVM = nil
            propertyVM = nil
            externalMergeTool = nil
            treeVM = TreeConflictViewModel(
                conflict: conflict,
                workingCopy: wc,
                resolver: session.conflictService
            )
        case .property:
            editorVM = nil
            treeVM = nil
            externalMergeTool = nil
            let vm = PropertyConflictViewModel(
                conflict: conflict,
                workingCopy: wc,
                resolver: session.conflictService
            )
            propertyVM = vm
            await vm.load()
        default:
            editorVM = nil
            treeVM = nil
            propertyVM = nil
            externalMergeTool = nil
            break
        }
    }

    private func refreshExternalMergeTool(for path: String) async {
        let settings = await session.settingsStore.settings()
        let tool = ExternalToolRuleResolver.tool(
            for: .merge,
            path: path,
            rules: settings.externalToolRules,
            legacyDiffTool: settings.externalDiffTool
        )
        guard listVM?.selectedConflictPath == path else { return }
        externalMergeTool = tool
    }

    private func openExternalMerge(_ conflict: ConflictInfo) async {
        guard !isOpeningExternalMerge,
              let record = workspaceController.selectedRecord else { return }
        let settings = await session.settingsStore.settings()
        guard let tool = ExternalToolRuleResolver.tool(
            for: .merge,
            path: conflict.path,
            rules: settings.externalToolRules,
            legacyDiffTool: settings.externalDiffTool
        ) else {
            statusText = "请先在设置中配置此扩展名的外置 Merge 工具。"
            return
        }
        externalMergeTool = tool
        isOpeningExternalMerge = true
        defer { isOpeningExternalMerge = false }
        do {
            _ = try await ExternalToolLaunchService(timeout: settings.processTimeout).openMerge(
                wc: URL(fileURLWithPath: record.localPath),
                conflict: conflict,
                tool: tool
            )
            statusText = "已打开外置 Merge（\(tool.name)），请确认结果后再标记已解决。"
        } catch {
            statusText = "外置 Merge 失败：\(error.localizedDescription)"
        }
    }

    private func kindDisplayLabel(_ kind: ConflictKind) -> LocalizedStringKey {
        switch kind {
        case .text: return "文本"
        case .tree: return "树"
        case .property: return "属性"
        case .unknown: return "未知"
        }
    }

    private func kindSystemImage(_ kind: ConflictKind) -> String {
        switch kind {
        case .text: return "doc.text"
        case .tree: return "folder.badge.questionmark"
        case .property: return "tag"
        case .unknown: return "questionmark.diamond"
        }
    }

    private func kindColor(_ kind: ConflictKind) -> Color {
        switch kind {
        case .text, .tree, .property: return conflictColour
        case .unknown: return .secondary
        }
    }

    private var conflictColour: Color {
        svnChangeColour(
            palette: session.settingsSnapshot.changeColours,
            role: .conflicted,
            colorScheme: colorScheme
        )
    }
}

private struct MacSvnMergeEditorPane: View {
    let conflict: ConflictInfo
    let editorVM: MergeEditorViewModel?
    let privacySettings: AIPrivacySettings
    @Binding var statusText: LocalizedStringKey?
    let externalMergeTool: ExternalDiffToolConfiguration?
    let isOpeningExternalMerge: Bool
    let conflictColour: Color
    let onSaved: () -> Void
    let onOpenExternalMerge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            conflictDetailHeader
            if let editorVM {
                conflictPrimaryActions(editorVM)
                Divider()

                switch editorVM.state {
                case .loading, .saving:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .error(let message):
                    ContentUnavailableView(
                        "加载失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(
                            LocalizedStringKey(MacSvnCoreModeErrorPresentation.message(message))
                        )
                    )
                    .help(message)
                case .saved:
                    ContentUnavailableView("已解决并写回", systemImage: "checkmark.seal")
                case .loaded, .idle:
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(editorVM.blocks.enumerated()), id: \.offset) { index, block in
                                blockView(index: index, block: block, editorVM: editorVM)
                            }
                        }
                        .padding()
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var conflictDetailHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label("文本", systemImage: "doc.text.fill")
                    .font(.headline)
                    .foregroundStyle(conflictColour)
                Spacer(minLength: 8)
                conflictStateLabel
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(conflict.path)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(conflict.path)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var conflictStateLabel: some View {
        if let editorVM {
            switch editorVM.state {
            case .idle:
                Label("等待加载", systemImage: "clock")
            case .loading:
                Label("加载中", systemImage: "arrow.triangle.2.circlepath")
            case .loaded where editorVM.hasUnsavedChanges:
                Label("未保存", systemImage: "circle.fill")
            case .loaded:
                Label("可处理", systemImage: "pencil.and.outline")
            case .saving:
                Label("正在保存", systemImage: "arrow.down.doc")
            case .saved:
                Label("已解决", systemImage: "checkmark.circle")
            case .error:
                Label("加载失败", systemImage: "exclamationmark.triangle")
            }
        } else {
            Label("加载中", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    private func conflictPrimaryActions(_ editorVM: MergeEditorViewModel) -> some View {
        HStack(spacing: 8) {
            Button {
                editorVM.previousConflict()
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("上一处")
            .accessibilityLabel("上一处")
            Button {
                editorVM.nextConflict()
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("下一处")
            .accessibilityLabel("下一处")
            conflictResolutionMenu(editorVM)
            conflictAssistMenu(editorVM)
            Spacer(minLength: 8)
            Label {
                Text("\(editorVM.unresolvedConflictCount)")
                    .font(.caption.monospacedDigit())
            } icon: {
                Image(systemName: "exclamationmark.circle")
            }
                .foregroundStyle(editorVM.unresolvedConflictCount == 0 ? .green : .orange)
                .help("未解决 \(editorVM.unresolvedConflictCount)")
                .accessibilityLabel("未解决 \(editorVM.unresolvedConflictCount)")
            Button("保存并 Resolve") {
                Task {
                    await editorVM.saveResolved()
                    handleSaveState(editorVM)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!editorVM.canSaveResolved)
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func conflictAssistMenu(_ editorVM: MergeEditorViewModel) -> some View {
        Menu {
            Button(isOpeningExternalMerge ? "启动中…" : "外置 Merge", systemImage: "arrow.up.forward.app") {
                onOpenExternalMerge()
            }
            .disabled(externalMergeTool == nil || isOpeningExternalMerge)
            Divider()
            Button("AI 建议当前", systemImage: "wand.and.stars") {
                Task {
                    await editorVM.requestAIResolutionForCurrentConflict(privacySettings: privacySettings)
                    handleAIAssistState(editorVM, success: "AI 冲突建议已应用（当前块）")
                }
            }
            Button("AI 预览全部", systemImage: "sparkles.rectangle.stack") {
                Task {
                    await editorVM.requestAIResolutionPreviewForAllConflicts(privacySettings: privacySettings)
                    handleAIAssistState(editorVM, success: "AI 冲突预览完成")
                }
            }
        } label: {
            Label("冲突辅助操作", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(externalMergeTool?.name ?? "冲突辅助操作")
        .accessibilityLabel("冲突辅助操作")
    }

    private func conflictResolutionMenu(_ editorVM: MergeEditorViewModel) -> some View {
        Menu {
            Button("采用 Mine") { editorVM.resolveCurrent(.takeMine) }
            Button("采用 Theirs") { editorVM.resolveCurrent(.takeTheirs) }
            Button("双方(Mine先)") { editorVM.resolveCurrent(.takeBoth(mineFirst: true)) }
            Divider()
            Button("整文件 Mine") {
                Task { await editorVM.resolveWholeFileMine(); handleSaveState(editorVM) }
            }
            Button("整文件 Theirs") {
                Task { await editorVM.resolveWholeFileTheirs(); handleSaveState(editorVM) }
            }
        } label: {
            Label("冲突解决策略", systemImage: "arrow.triangle.branch")
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("冲突解决策略")
        .accessibilityLabel("冲突解决策略")
    }

    private func handleAIAssistState(_ editorVM: MergeEditorViewModel, success: LocalizedStringKey) {
        switch editorVM.aiConflictAssistState {
        case .error(let message):
            statusText = LocalizedStringKey(message)
        case .suggested, .previewed:
            statusText = success
        case .idle, .suggesting:
            break
        }
    }

    @ViewBuilder
    private func blockView(index: Int, block: MergeBlock, editorVM: MergeEditorViewModel) -> some View {
        switch block {
        case .stable(let lines):
            Text(lines.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.secondary.opacity(0.08))
        case .conflict(let hunk):
            VStack(alignment: .leading, spacing: 6) {
                Text("冲突块 #\(index) \(hunk.resolution == nil ? "未解决" : "已解决")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hunk.resolution == nil ? .red : .green)
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 120), alignment: .topLeading),
                        GridItem(.flexible(minimum: 120), alignment: .topLeading),
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    pane("Mine", hunk.mineLines, .blue)
                    pane("Base", hunk.baseLines, .secondary)
                    pane("Theirs", hunk.theirsLines, .orange)
                    pane("Result", hunk.resolvedLines(), .green)
                }
            }
            .padding(8)
            .background((hunk.resolution == nil ? conflictColour : Color.green).opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(editorVM.currentBlockIndex == index ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
    }

    private func pane(_ title: String, _ lines: [String]?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(color)
            if let lines {
                Text(lines.joined(separator: "\n"))
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("尚未选择解决结果")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(6)
        .background(color.opacity(0.08))
    }

    private func handleSaveState(_ editorVM: MergeEditorViewModel) {
        switch editorVM.state {
        case .saved:
            statusText = "冲突已 resolve"
            onSaved()
        case .error(let message):
            statusText = LocalizedStringKey(message)
        default:
            break
        }
    }
}

private struct MacSvnTreeConflictPane: View {
    let treeVM: TreeConflictViewModel?
    let onResolved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let treeVM {
                Text(treeVM.path)
                    .font(.headline)
                LabeledContent("operation", value: treeVM.operation ?? "-")
                LabeledContent("action", value: treeVM.action ?? "-")
                LabeledContent("reason", value: treeVM.reason ?? "-")
                HStack {
                    Button("保留本地") {
                        Task {
                            await treeVM.resolve(.keepLocal)
                            if case .resolved = treeVM.state { onResolved() }
                        }
                    }
                    Button("接受远端") {
                        Task {
                            await treeVM.resolve(.acceptRemote)
                            if case .resolved = treeVM.state { onResolved() }
                        }
                    }
                }
                if case .error(let message) = treeVM.state {
                    Text(message).foregroundStyle(.red)
                }
                if case .resolved = treeVM.state {
                    Text("树冲突已处理").foregroundStyle(.green)
                }
            } else {
                ProgressView()
            }
            Spacer()
        }
        .padding()
    }
}

/// 属性冲突：展示 Mine / Base / Theirs 侧文件内容，选择保留一方后 resolve。
private struct MacSvnPropertyConflictPane: View {
    let propertyVM: PropertyConflictViewModel?
    let onResolved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let propertyVM {
                Text(propertyVM.path)
                    .font(.headline)
                Text("属性冲突：选择保留本地或远端属性值")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                switch propertyVM.state {
                case .loading:
                    ProgressView("加载属性侧文件…")
                case .error(let message):
                    Text(message).foregroundStyle(.red)
                case .resolved:
                    Text("属性冲突已处理").foregroundStyle(.green)
                case .idle, .loaded, .resolving:
                    HStack(alignment: .top, spacing: 12) {
                        propertyPane("Mine", propertyVM.mineValue, .blue)
                        propertyPane("Base", propertyVM.baseValue, .secondary)
                        propertyPane("Theirs", propertyVM.theirsValue, .orange)
                    }
                    HStack {
                        Button("保留 Mine") {
                            Task {
                                await propertyVM.resolve(.keepMine)
                                if case .resolved = propertyVM.state { onResolved() }
                            }
                        }
                        .disabled(propertyVM.state == .resolving)
                        Button("保留 Theirs") {
                            Task {
                                await propertyVM.resolve(.keepTheirs)
                                if case .resolved = propertyVM.state { onResolved() }
                            }
                        }
                        .disabled(propertyVM.state == .resolving)
                    }
                }
            } else {
                ProgressView()
            }
            Spacer()
        }
        .padding()
    }

    private func propertyPane(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(color)
            ScrollView {
                Text(value.isEmpty ? "（空）" : value)
                    .font(.system(.caption2, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 120)
            .padding(6)
            .background(color.opacity(0.08))
        }
    }
}
