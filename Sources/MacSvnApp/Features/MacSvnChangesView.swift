import SwiftUI
import MacSvnCore

/// 变更页：绑定 ChangesViewModel + WorkingCopyActionsViewModel。
public struct MacSvnChangesView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let svnService: SvnService
    private let navigator: MacSvnAppNavigator?
    private let session: MacSvnAppSession?
    /// 嵌入变更工作区时隐藏大标题、收紧边距。
    private let embedded: Bool
    /// 深链 / ⌘K 注入的初始选中。
    private let initialSelectedPaths: Set<String>
    /// 选中变化时回调主路径（供同屏 Diff）。
    private let onFocusedPathChange: ((String?) -> Void)?

    @State private var changesVM: ChangesViewModel?
    @State private var actionsVM: WorkingCopyActionsViewModel?
    @State private var filterMode: FilterMode = .all
    @State private var displayMode: ChangesDisplayMode = .flat
    @State private var searchText = ""
    @State private var selectedPaths: Set<String> = []
    @State private var confirmRevert = false
    @State private var confirmDelete = false
    @State private var showAddSheet = false
    @State private var showCleanupSheet = false
    @State private var showRevertSheet = false
    @State private var showRenameSheet = false
    @State private var renameNewName = ""
    @State private var addSelectedPaths: Set<String> = []
    @State private var revertRecursive = false
    @State private var cleanupOptions = SvnCleanupOptions()
    @State private var statusBanner: String?
    @State private var setDepth: SvnDepth = .infinity
    @State private var showSetDepth = false

    private enum FilterMode: String, CaseIterable, Identifiable {
        case all = "全部"
        case modified = "已修改"
        case conflicts = "冲突"
        var id: String { rawValue }
    }

    public init(
        workspaceController: MacSvnWorkspaceController,
        statusProvider: SvnService,
        navigator: MacSvnAppNavigator? = nil,
        session: MacSvnAppSession? = nil,
        embedded: Bool = false,
        initialSelectedPaths: Set<String> = [],
        onFocusedPathChange: ((String?) -> Void)? = nil
    ) {
        self.workspaceController = workspaceController
        self.svnService = statusProvider
        self.navigator = navigator
        self.session = session
        self.embedded = embedded
        self.initialSelectedPaths = initialSelectedPaths
        self.onFocusedPathChange = onFocusedPathChange
        _selectedPaths = State(initialValue: initialSelectedPaths)
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
            if let refreshed = changesVM?.lastRefreshedAt {
                HStack(spacing: 8) {
                    Text("本地 status 刷新于 \(Self.refreshFormatter.string(from: refreshed))")
                    if changesVM?.includesRepositoryCheck == true {
                        Text("· 已对照仓库")
                            .foregroundStyle(.tint)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, embedded ? 12 : 24)
                .padding(.bottom, 4)
            }
            content
        }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await bindAndRefresh() }
        }
        .onChange(of: initialSelectedPaths) { _, newValue in
            // 深链 / ⌘K / 工作区种子路径会在 init 之后更新，必须同步选中
            guard !newValue.isEmpty else { return }
            selectedPaths = newValue
            onFocusedPathChange?(newValue.sorted().first)
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
        .confirmationDialog(
            "确认从版本库调度删除选中路径？本地文件将被删除（未提交前可用还原撤销）。",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task { await runDelete() }
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showAddSheet) {
            addSheet
        }
        .sheet(isPresented: $showCleanupSheet) {
            cleanupSheet
        }
        .sheet(isPresented: $showRevertSheet) {
            revertSheet
        }
        .sheet(isPresented: $showRenameSheet) {
            renameSheet
        }
        .sheet(isPresented: $showSetDepth) {
            VStack(alignment: .leading, spacing: 16) {
                Text("调整工作副本深度（svn update --set-depth）")
                    .font(.headline)
                Picker("深度", selection: $setDepth) {
                    Text("empty").tag(SvnDepth.empty)
                    Text("files").tag(SvnDepth.files)
                    Text("immediates").tag(SvnDepth.immediates)
                    Text("infinity").tag(SvnDepth.infinity)
                }
                .pickerStyle(.radioGroup)
                Text("将作用于选中路径；未选中时作用于 WC 根。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("取消") { showSetDepth = false }
                    Spacer()
                    Button("执行") {
                        showSetDepth = false
                        Task { await runSetDepth() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 420)
        }
    }

    private var header: some View {
        HStack {
            if !embedded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("变更")
                        .font(.largeTitle.weight(.semibold))
                    if let path = workspaceController.selectedRecord?.localPath {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("变更")
                    .font(.headline)
            }
            Spacer()
            Picker("筛选", selection: $filterMode) {
                ForEach(FilterMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: embedded ? 220 : 280)
            Picker("视图", selection: $displayMode) {
                Text("平铺").tag(ChangesDisplayMode.flat)
                Text("树").tag(ChangesDisplayMode.tree)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 140)
            .onChange(of: displayMode) { _, newValue in
                changesVM?.displayMode = newValue
            }
            TextField("搜索文件名", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: embedded ? 140 : 220)
            Menu("列") {
                ForEach(CFMColumnID.allCases, id: \.self) { column in
                    Button {
                        Task { await toggleColumn(column) }
                    } label: {
                        HStack {
                            Text(column.displayName)
                            if changesVM?.columnConfiguration.isVisible(column) == true {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(column == .path)
                }
            }
            .disabled(changesVM == nil)
            Button("刷新") {
                Task { await changesVM?.refresh() }
            }
            .disabled(changesVM == nil || actionsVM?.isRunning == true)
            Button("检查仓库") {
                Task { await changesVM?.checkRepository() }
            }
            .disabled(changesVM == nil || actionsVM?.isRunning == true)
            .help("对照远端（svn status -u），按颜色区分仅本地/仅远端/双方变更")
        }
        .padding(embedded ? 12 : 24)
        .onChange(of: filterMode) { _, _ in applyFilters() }
        .onChange(of: searchText) { _, _ in applyFilters() }
        .onChange(of: selectedPaths) { _, newValue in
            onFocusedPathChange?(newValue.sorted().first)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("更新") {
                Task { await runUpdate() }
            }
            .disabled(actionsVM == nil || actionsVM?.isRunning == true)

            Button("清理") {
                cleanupOptions = .default
                showCleanupSheet = true
            }
            .disabled(actionsVM == nil || actionsVM?.isRunning == true)

            Button("添加") {
                prepareAddSheet()
                showAddSheet = true
            }
            .disabled(actionsVM?.isRunning == true || changesVM == nil)

            Button("删除") {
                confirmDelete = true
            }
            .disabled(selectedPaths.isEmpty || actionsVM?.isRunning == true)

            Button("还原…") {
                revertRecursive = false
                showRevertSheet = true
            }
            .disabled(selectedPaths.isEmpty || actionsVM?.isRunning == true)

            Button("重命名…") {
                prepareRenameSheet()
                showRenameSheet = true
            }
            .disabled(selectedPaths.count != 1 || actionsVM?.isRunning == true)

            Button("修复移动") {
                Task { await runRepairMove() }
            }
            .disabled(!canRepairMove || actionsVM?.isRunning == true)

            Button("修复复制") {
                Task { await runRepairCopy() }
            }
            .disabled(!canRepairCopy || actionsVM?.isRunning == true)

            Button("调整深度…") {
                showSetDepth = true
            }
            .disabled(actionsVM == nil || actionsVM?.isRunning == true)

            Button("忽略选中") {
                Task { await ignoreSelected() }
            }
            .disabled(selectedPaths.isEmpty || session == nil)

            if let conflictCount = conflictCount, conflictCount > 0 {
                Button("解决冲突 (\(conflictCount))") {
                    navigator?.selectMode(.conflicts)
                }
                .tint(.red)
            }

            if actionsVM?.isRunning == true {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()
            Text("已选 \(selectedPaths.count) 项")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, embedded ? 12 : 24)
        .padding(.bottom, embedded ? 8 : 12)
    }

    private var conflictCount: Int? {
        guard let changesVM, case .loaded = changesVM.state else { return nil }
        return changesVM.visibleFlatEntries.filter { $0.itemStatus == .conflicted || $0.isTreeConflict }.count
    }

    /// 当前多选是否满足 Repair Move 配对（missing + unversioned）。
    private var canRepairMove: Bool {
        guard let changesVM else { return false }
        return RepairMoveCopyPairing.canRepair(
            kind: .move,
            selectedPaths: selectedPaths,
            statuses: changesVM.entries
        )
    }

    /// 当前多选是否满足 Repair Copy 配对（已版本化 + unversioned）。
    private var canRepairCopy: Bool {
        guard let changesVM else { return false }
        return RepairMoveCopyPairing.canRepair(
            kind: .copy,
            selectedPaths: selectedPaths,
            statuses: changesVM.entries
        )
    }

    @ViewBuilder
    private var content: some View {
        if workspaceController.selectedRecord == nil {
            ContentUnavailableView(
                "未选择工作副本",
                systemImage: "externaldrive",
                description: Text("请先在左侧列表添加并选中工作副本")
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
                                .listRowBackground(highlightColor(changesVM.highlight(for: entry)))
                        }
                    } else {
                        OutlineGroup(changesVM.visibleTreeEntries, children: \.outlineChildren) { node in
                            treeRow(node)
                                .tag(node.path)
                                .listRowBackground(
                                    node.fileStatus.map { highlightColor(changesVM.highlight(for: $0)) } ?? Color.clear
                                )
                        }
                    }
                }
                .contextMenu {
                    Button("重命名…") {
                        prepareRenameSheet()
                        showRenameSheet = true
                    }
                    .disabled(selectedPaths.count != 1)

                    Button("修复移动") {
                        Task { await runRepairMove() }
                    }
                    .disabled(!canRepairMove)

                    Button("修复复制") {
                        Task { await runRepairCopy() }
                    }
                    .disabled(!canRepairCopy)
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func flatRow(_ entry: FileStatus) -> some View {
        let columns = changesVM?.visibleColumns ?? CFMColumnID.allCases
        return HStack(spacing: 8) {
            ForEach(columns, id: \.self) { column in
                switch column {
                case .textStatus:
                    Text(statusLabel(entry.itemStatus))
                        .font(.caption.monospaced())
                        .frame(width: 28, alignment: .leading)
                        .foregroundStyle(statusColor(entry.itemStatus))
                case .remoteStatus:
                    Text(entry.remoteItemStatus.map(statusLabel) ?? "—")
                        .font(.caption.monospaced())
                        .frame(width: 28, alignment: .leading)
                        .foregroundStyle(.secondary)
                case .path:
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.path)
                        if entry.isTreeConflict, columns.contains(.treeConflict) == false {
                            Text("树冲突")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .revision:
                    Text(entry.revision.map { "r\($0.value)" } ?? "—")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                case .treeConflict:
                    Text(entry.isTreeConflict ? "是" : "")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .frame(width: 40, alignment: .center)
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
        // 切换 WC 时关闭对话框，避免把上一副本的勾选路径提交到当前副本
        dismissActionSheets()
        guard let record = workspaceController.selectedRecord, record.isValid else {
            changesVM = nil
            actionsVM = nil
            selectedPaths = []
            return
        }
        let wc = URL(fileURLWithPath: record.localPath)
        let cfmColumns: CFMColumnConfiguration
        if let session {
            cfmColumns = await session.settingsStore.settings().cfmColumns
        } else {
            cfmColumns = .default
        }
        let changes = ChangesViewModel(
            workingCopy: wc,
            statusProvider: svnService,
            columnConfiguration: cfmColumns
        )
        let actions = WorkingCopyActionsViewModel(
            workingCopy: wc,
            actionProvider: svnService,
            statusProvider: svnService
        )
        changesVM = changes
        actionsVM = actions
        if !initialSelectedPaths.isEmpty {
            selectedPaths = initialSelectedPaths
            onFocusedPathChange?(initialSelectedPaths.sorted().first)
        } else {
            selectedPaths = []
        }
        applyFilters()
        await changes.refresh()
    }

    /// 关闭 Add/Cleanup/Revert/Delete 等对话框并清空临时勾选，防止跨 WC 误操作。
    private func dismissActionSheets() {
        showAddSheet = false
        showCleanupSheet = false
        showRevertSheet = false
        showRenameSheet = false
        confirmDelete = false
        confirmRevert = false
        addSelectedPaths = []
        renameNewName = ""
        revertRecursive = false
        cleanupOptions = .default
    }

    private func toggleColumn(_ column: CFMColumnID) async {
        guard let changesVM else { return }
        let currentlyVisible = changesVM.columnConfiguration.isVisible(column)
        changesVM.setColumnVisible(column, visible: !currentlyVisible)
        guard let session else { return }
        var settings = await session.settingsStore.settings()
        settings.cfmColumns = changesVM.columnConfiguration
        do {
            try await session.settingsStore.update(settings)
        } catch {
            statusBanner = "列配置保存失败：\(error.localizedDescription)"
        }
    }

    private static let refreshFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

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
        // 有多选时按选中路径更新（≥2 时 Service 层会钉住 HEAD 防 mixed-rev）
        await actionsVM.update(paths: Array(selectedPaths))
        await syncAfterAction(actionsVM, changesVM)
    }

    private func runSetDepth() async {
        guard let actionsVM, let changesVM else { return }
        let paths = Array(selectedPaths)
        await actionsVM.update(paths: paths, setDepth: setDepth)
        await syncAfterAction(actionsVM, changesVM)
        if case .updateCompleted = actionsVM.state {
            statusBanner = "已设置深度 \(String(describing: setDepth))"
        }
    }

    /// 将选中路径的 basename 追加到父目录 `svn:ignore`（FR-ST-05）。
    private func ignoreSelected() async {
        guard let session, let record = workspaceController.selectedRecord, let changesVM else { return }
        let wc = URL(fileURLWithPath: record.localPath)
        do {
            for path in selectedPaths {
                let url = URL(fileURLWithPath: path, relativeTo: wc)
                let parentRel = url.deletingLastPathComponent().relativePath
                let target = parentRel.isEmpty || parentRel == "." ? "." : parentRel
                let pattern = url.lastPathComponent
                let existing = try await session.svnService.propertyValue(wc: wc, target: target, name: "svn:ignore")
                var lines = (existing?.value ?? "")
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)
                if !lines.contains(pattern) {
                    if lines.last == "" { lines.removeLast() }
                    lines.append(pattern)
                }
                let value = lines.joined(separator: "\n") + "\n"
                let vm = PropertyViewModel(workingCopy: wc, target: target, provider: session.svnService)
                await vm.load()
                await vm.save(name: "svn:ignore", value: value)
            }
            statusBanner = "已写入 svn:ignore"
            await changesVM.refresh()
            selectedPaths = []
        } catch {
            statusBanner = "忽略失败：\(error.localizedDescription)"
        }
    }

    private func runCleanup() async {
        guard let actionsVM, let changesVM else { return }
        await actionsVM.cleanup(options: cleanupOptions)
        await syncAfterAction(actionsVM, changesVM)
    }

    private func prepareAddSheet() {
        guard let changesVM else { return }
        addSelectedPaths = AddCandidatesPolicy.defaultSelectedPaths(
            from: changesVM.entries,
            preselected: selectedPaths
        )
    }

    private func runAddFromSheet() async {
        guard let actionsVM, let changesVM else { return }
        let paths = Array(addSelectedPaths).sorted()
        guard !paths.isEmpty else {
            statusBanner = "未勾选可添加项"
            return
        }
        showAddSheet = false
        await actionsVM.add(paths: paths)
        await syncAfterAction(actionsVM, changesVM)
    }

    private func runDelete() async {
        guard let actionsVM, let changesVM else { return }
        await actionsVM.delete(paths: Array(selectedPaths))
        await syncAfterAction(actionsVM, changesVM)
    }

    private func runRevert(confirmed: Bool) async {
        guard let actionsVM, let changesVM else { return }
        await actionsVM.revert(paths: Array(selectedPaths), recursive: revertRecursive, confirmed: confirmed)
        await syncAfterAction(actionsVM, changesVM)
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("添加未版本文件")
                .font(.headline)
            Text("勾选要纳入版本控制的路径（对齐小乌龟 Add 勾选列表）。")
                .font(.caption)
                .foregroundStyle(.secondary)
            let candidates = AddCandidatesPolicy.candidates(from: changesVM?.entries ?? [])
            if candidates.isEmpty {
                Text("当前没有未版本项。")
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(candidates, id: \.path) { status in
                        Toggle(isOn: Binding(
                            get: { addSelectedPaths.contains(status.path) },
                            set: { selected in
                                if selected {
                                    addSelectedPaths.insert(status.path)
                                } else {
                                    addSelectedPaths.remove(status.path)
                                }
                            }
                        )) {
                            Text(status.path)
                        }
                    }
                }
                .frame(minHeight: 220)
            }
            HStack {
                Button("取消") { showAddSheet = false }
                Spacer()
                Button("添加") {
                    Task { await runAddFromSheet() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(addSelectedPaths.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480, height: 360)
    }

    private var cleanupSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("清理工作副本")
                .font(.headline)
            Toggle("打断锁（--break-locks）", isOn: $cleanupOptions.breakLocks)
            Toggle("清理 pristine（--vacuum-pristines）", isOn: $cleanupOptions.vacuumPristines)
            Toggle("包含外部项（--include-externals）", isOn: $cleanupOptions.includeExternals)
            Text("默认仅执行 `svn cleanup`；危险的删除未版本请用独立命令（#16）。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("取消") { showCleanupSheet = false }
                Spacer()
                Button("执行清理") {
                    showCleanupSheet = false
                    Task { await runCleanup() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var revertSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("还原本地修改")
                .font(.headline)
            Text("已选 \(selectedPaths.count) 项")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("递归还原目录（--recursive）", isOn: $revertRecursive)
            if selectedPaths.count == 1, let path = selectedPaths.sorted().first {
                Button("查看 Diff：\(path)") {
                    _ = navigator?.perform(command: .diff, paths: [path])
                }
            }
            Text("还原不可撤销未保存的本地修改。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("取消") { showRevertSheet = false }
                Spacer()
                Button("还原", role: .destructive) {
                    showRevertSheet = false
                    Task { await runRevert(confirmed: true) }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("重命名")
                .font(.headline)
            if let source = selectedPaths.sorted().first {
                Text("当前：\(source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("新名称", text: $renameNewName)
                Text("仅同目录改名；跨目录请用移动（#36）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("取消") { showRenameSheet = false }
                Spacer()
                Button("重命名") {
                    Task { await runRenameFromSheet() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    selectedPaths.count != 1
                        || renameNewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func prepareRenameSheet() {
        guard let path = selectedPaths.sorted().first else {
            renameNewName = ""
            return
        }
        renameNewName = (path as NSString).lastPathComponent
    }

    private func runRenameFromSheet() async {
        guard let actionsVM, let changesVM else { return }
        guard let source = selectedPaths.sorted().first, selectedPaths.count == 1 else {
            statusBanner = "请先选中恰好一项再重命名"
            showRenameSheet = false
            return
        }
        let existing = Set(changesVM.entries.map(\.path))
        showRenameSheet = false
        await actionsVM.rename(sourcePath: source, newName: renameNewName, existingPaths: existing)
        await syncAfterAction(actionsVM, changesVM)
    }

    private func runRepairMove() async {
        guard let actionsVM, let changesVM else { return }
        await actionsVM.repairMove(selectedPaths: selectedPaths, statuses: changesVM.entries)
        await syncAfterAction(actionsVM, changesVM)
        if case .completed(.repairMove) = actionsVM.state {
            statusBanner = "已修复移动"
        }
    }

    private func runRepairCopy() async {
        guard let actionsVM, let changesVM else { return }
        await actionsVM.repairCopy(selectedPaths: selectedPaths, statuses: changesVM.entries)
        await syncAfterAction(actionsVM, changesVM)
        if case .completed(.repairCopy) = actionsVM.state {
            statusBanner = "已修复复制"
        }
    }

    private func syncAfterAction(
        _ actionsVM: WorkingCopyActionsViewModel,
        _ changesVM: ChangesViewModel
    ) async {
        switch actionsVM.state {
        case .updateCompleted(let summary):
            statusBanner = "更新完成：更新 \(summary.updated) / 新增 \(summary.added) / 删除 \(summary.deleted) / 冲突 \(summary.conflicted)"
            await refreshAfterMutation(changesVM)
            selectedPaths = []
            if summary.conflicted > 0 {
                navigator?.selectMode(.conflicts)
                navigator?.lastAutomationMessage = "更新产生 \(summary.conflicted) 个冲突，已切换到冲突工作区"
            }
        case .completed(let op):
            statusBanner = "\(label(for: op)) 完成"
            await refreshAfterMutation(changesVM)
            selectedPaths = []
        case .error(let message):
            statusBanner = "操作失败：\(message)"
            // 可能已发生部分文件系统挪动，必须刷新以免基于过期 status 再次操作
            await refreshAfterMutation(changesVM)
        case .confirmationRequired:
            confirmRevert = true
        default:
            break
        }
    }

    /// 写操作后刷新：若当前处于「已对照仓库」则继续 `-u`，避免丢失远端高亮。
    private func refreshAfterMutation(_ changesVM: ChangesViewModel) async {
        if changesVM.includesRepositoryCheck {
            await changesVM.checkRepository()
        } else {
            await changesVM.refresh()
        }
    }

    private func label(for operation: WorkingCopyOperation) -> String {
        switch operation {
        case .update: return "更新"
        case .add: return "添加"
        case .delete: return "删除"
        case .rename: return "重命名"
        case .repairMove: return "修复移动"
        case .repairCopy: return "修复复制"
        case .revert: return "还原"
        case .cleanup: return "清理"
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

    /// CFM 行底色：仅本地 / 仅远端 / 双方 / 冲突
    private func highlightColor(_ highlight: CFMChangeHighlight) -> Color {
        switch highlight {
        case .none:
            return Color.clear
        case .localOnly:
            return Color.blue.opacity(0.10)
        case .remoteOnly:
            return Color.purple.opacity(0.12)
        case .both:
            return Color.orange.opacity(0.14)
        case .conflicted:
            return Color.red.opacity(0.16)
        }
    }
}

private extension FileStatusNode {
    /// OutlineGroup 需要 Optional children：叶子为 nil。
    var outlineChildren: [FileStatusNode]? {
        children.isEmpty ? nil : children
    }
}
