import SwiftUI
import MacSvnCore

/// 变更页：绑定 ChangesViewModel + WorkingCopyActionsViewModel。
public struct MacSvnChangesView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let svnService: SvnService
    private let navigator: MacSvnAppNavigator?

    @State private var changesVM: ChangesViewModel?
    @State private var actionsVM: WorkingCopyActionsViewModel?
    @State private var filterMode: FilterMode = .all
    @State private var displayMode: ChangesDisplayMode = .flat
    @State private var searchText = ""
    @State private var selectedPaths: Set<String> = []
    @State private var confirmRevert = false
    @State private var statusBanner: String?

    private enum FilterMode: String, CaseIterable, Identifiable {
        case all = "全部"
        case modified = "已修改"
        case conflicts = "冲突"
        var id: String { rawValue }
    }

    public init(
        workspaceController: MacSvnWorkspaceController,
        statusProvider: SvnService,
        navigator: MacSvnAppNavigator? = nil
    ) {
        self.workspaceController = workspaceController
        self.svnService = statusProvider
        self.navigator = navigator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            actionBar
            if let statusBanner {
                Text(statusBanner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
            content
        }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await bindAndRefresh() }
        }
        .task { await bindAndRefresh() }
        .confirmationDialog(
            "确认还原选中文件的本地修改？此操作不可撤销。",
            isPresented: $confirmRevert,
            titleVisibility: .visible
        ) {
            Button("还原", role: .destructive) {
                Task { await runRevert(confirmed: true) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("变更")
                    .font(.largeTitle.weight(.semibold))
                if let path = workspaceController.selectedRecord?.localPath {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("筛选", selection: $filterMode) {
                ForEach(FilterMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            Picker("视图", selection: $displayMode) {
                Text("平铺").tag(ChangesDisplayMode.flat)
                Text("树").tag(ChangesDisplayMode.tree)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)
            .onChange(of: displayMode) { _, newValue in
                changesVM?.displayMode = newValue
            }
            TextField("搜索文件名", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            Button("刷新") {
                Task { await changesVM?.refresh() }
            }
            .disabled(changesVM == nil || actionsVM?.isRunning == true)
        }
        .padding(24)
        .onChange(of: filterMode) { _, _ in applyFilters() }
        .onChange(of: searchText) { _, _ in applyFilters() }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("Update") {
                Task { await runUpdate() }
            }
            .disabled(actionsVM == nil || actionsVM?.isRunning == true)

            Button("Cleanup") {
                Task { await runCleanup() }
            }
            .disabled(actionsVM == nil || actionsVM?.isRunning == true)

            Button("Add") {
                Task { await runAdd() }
            }
            .disabled(selectedPaths.isEmpty || actionsVM?.isRunning == true)

            Button("Delete") {
                Task { await runDelete() }
            }
            .disabled(selectedPaths.isEmpty || actionsVM?.isRunning == true)

            Button("Revert…") {
                confirmRevert = true
            }
            .disabled(selectedPaths.isEmpty || actionsVM?.isRunning == true)

            if actionsVM?.isRunning == true {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()
            Text("已选 \(selectedPaths.count) 项")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if workspaceController.selectedRecord == nil {
            ContentUnavailableView(
                "未选择工作副本",
                systemImage: "externaldrive",
                description: Text("请先在「工作副本」中添加并选中目录")
            )
        } else if let changesVM {
            switch changesVM.state {
            case .idle, .loading:
                ProgressView("正在读取 status…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                ContentUnavailableView(
                    "读取失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .loaded:
                List(selection: $selectedPaths) {
                    if displayMode == .flat {
                        ForEach(changesVM.visibleFlatEntries, id: \.path) { entry in
                            flatRow(entry)
                                .tag(entry.path)
                        }
                    } else {
                        OutlineGroup(changesVM.visibleTreeEntries, children: \.outlineChildren) { node in
                            treeRow(node)
                                .tag(node.path)
                        }
                    }
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func flatRow(_ entry: FileStatus) -> some View {
        HStack {
            Text(statusLabel(entry.itemStatus))
                .font(.caption.monospaced())
                .frame(width: 28, alignment: .leading)
                .foregroundStyle(statusColor(entry.itemStatus))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.path)
                if entry.isTreeConflict {
                    Text("树冲突")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func treeRow(_ node: FileStatusNode) -> some View {
        HStack {
            if !node.isDirectory {
                Text(statusLabel(node.itemStatus))
                    .font(.caption.monospaced())
                    .frame(width: 28, alignment: .leading)
                    .foregroundStyle(statusColor(node.itemStatus))
            } else {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
            }
            Text(node.name)
            if node.isTreeConflict {
                Text("树冲突")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func bindAndRefresh() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            changesVM = nil
            actionsVM = nil
            selectedPaths = []
            return
        }
        let wc = URL(fileURLWithPath: record.localPath)
        let changes = ChangesViewModel(workingCopy: wc, statusProvider: svnService)
        let actions = WorkingCopyActionsViewModel(
            workingCopy: wc,
            actionProvider: svnService,
            statusProvider: svnService
        )
        changesVM = changes
        actionsVM = actions
        selectedPaths = []
        applyFilters()
        await changes.refresh()
    }

    private func applyFilters() {
        guard let changesVM else { return }
        changesVM.searchText = searchText
        switch filterMode {
        case .all:
            changesVM.filter = .all
        case .modified:
            changesVM.filter = .items([.modified, .added, .deleted, .replaced, .missing])
        case .conflicts:
            changesVM.filter = .conflicts
        }
    }

    private func runUpdate() async {
        guard let actionsVM, let changesVM else { return }
        await actionsVM.update()
        await syncAfterAction(actionsVM, changesVM)
    }

    private func runCleanup() async {
        guard let actionsVM, let changesVM else { return }
        await actionsVM.cleanup()
        await syncAfterAction(actionsVM, changesVM)
    }

    private func runAdd() async {
        guard let actionsVM, let changesVM else { return }
        await actionsVM.add(paths: Array(selectedPaths))
        await syncAfterAction(actionsVM, changesVM)
    }

    private func runDelete() async {
        guard let actionsVM, let changesVM else { return }
        await actionsVM.delete(paths: Array(selectedPaths))
        await syncAfterAction(actionsVM, changesVM)
    }

    private func runRevert(confirmed: Bool) async {
        guard let actionsVM, let changesVM else { return }
        await actionsVM.revert(paths: Array(selectedPaths), confirmed: confirmed)
        await syncAfterAction(actionsVM, changesVM)
    }

    private func syncAfterAction(
        _ actionsVM: WorkingCopyActionsViewModel,
        _ changesVM: ChangesViewModel
    ) async {
        switch actionsVM.state {
        case .updateCompleted(let summary):
            statusBanner = "Update 完成：更新 \(summary.updated) / 新增 \(summary.added) / 删除 \(summary.deleted) / 冲突 \(summary.conflicted)"
            await changesVM.refresh()
            selectedPaths = []
            if summary.conflicted > 0 {
                navigator?.selectedRoute = .merge
                navigator?.lastAutomationMessage = "Update 产生 \(summary.conflicted) 个冲突，已跳转冲突页"
            }
        case .completed(let op):
            statusBanner = "\(label(for: op)) 完成"
            await changesVM.refresh()
            selectedPaths = []
        case .error(let message):
            statusBanner = "操作失败：\(message)"
        case .confirmationRequired:
            confirmRevert = true
        default:
            break
        }
    }

    private func label(for operation: WorkingCopyOperation) -> String {
        switch operation {
        case .update: return "Update"
        case .add: return "Add"
        case .delete: return "Delete"
        case .revert: return "Revert"
        case .cleanup: return "Cleanup"
        }
    }

    private func statusLabel(_ status: ItemStatus) -> String {
        switch status {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .unversioned: return "?"
        case .missing: return "!"
        case .conflicted: return "C"
        case .replaced: return "R"
        case .ignored: return "I"
        case .external: return "X"
        case .normal: return " "
        default: return String(status.rawValue.prefix(1)).uppercased()
        }
    }

    private func statusColor(_ status: ItemStatus) -> Color {
        switch status {
        case .conflicted: return .red
        case .added: return .green
        case .deleted: return .orange
        case .modified, .replaced: return .blue
        default: return .secondary
        }
    }
}

private extension FileStatusNode {
    /// OutlineGroup 需要 Optional children：叶子为 nil。
    var outlineChildren: [FileStatusNode]? {
        children.isEmpty ? nil : children
    }
}
