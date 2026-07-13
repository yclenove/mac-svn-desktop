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
    @State private var confirmDeleteKeepLocal = false
    @State private var confirmDeleteUnversioned = false
    @State private var confirmMarkResolved = false
    @State private var showAddSheet = false
    @State private var showDeleteUnversionedSheet = false
    @State private var showCleanupSheet = false
    @State private var showRevertSheet = false
    @State private var showRenameSheet = false
    @State private var showCaseConflictRepairSheet = false
    @State private var showIgnoreSheet = false
    @State private var showCopyMoveSheet = false
    @State private var renameNewName = ""
    @State private var caseConflictNewName = ""
    @State private var ignoreKind: IgnorePatternKind = .exactFilename
    @State private var copyMoveKind: CopyMoveKind = .move
    @State private var copyMoveDestination = ""
    @State private var addSelectedPaths: Set<String> = []
    @State private var unversionedDeletionCandidates: [FileStatus] = []
    @State private var unversionedDeletionSelectedPaths: Set<String> = []
    @State private var revertRecursive = false
    @State private var cleanupOptions = SvnCleanupOptions()
    @State private var statusBanner: String?
    @State private var setDepth: SvnDepth = .infinity
    @State private var showUpdateToRevisionSheet = false
    @State private var updateToRevisionText = ""
    @State private var updateIgnoreExternals = false
    @State private var showChangelistSheet = false
    @State private var changelistName = ""
    @State private var changelistDepth: SvnDepth = .empty
    @State private var changelistOperation: ChangelistOperation = .assign

    private enum FilterMode: String, CaseIterable, Identifiable {
        case all = "全部"
        case modified = "已修改"
        case conflicts = "冲突"
        var id: String { rawValue }
    }

    private enum ChangelistOperation: String, CaseIterable, Identifiable {
        case assign = "移动到列表"
        case remove = "移出列表"
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
        configuredBody
            .onChange(of: navigator?.pendingCopyMoveIntent) { _, _ in
                consumePendingCopyMoveIntentIfReady()
            }
    }

    private var configuredBody: some View {
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
        .onChange(of: navigator?.pendingChangelistIntent) { _, _ in
            consumePendingChangelistIntent()
        }
        .onChange(of: navigator?.pendingDeleteIntent) { _, _ in
            consumePendingDeleteIntent()
        }
        .task {
            await bindAndRefresh()
            consumePendingChangelistIntent()
            consumePendingDeleteIntent()
            consumePendingCopyMoveIntentIfReady()
        }
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
        .confirmationDialog(
            "确认从版本库删除选中路径，但保留本地文件？提交前可用还原撤销版本库删除。",
            isPresented: $confirmDeleteKeepLocal,
            titleVisibility: .visible
        ) {
            Button("删除并保留本地", role: .destructive) {
                Task { await runDeleteKeepingLocal() }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "确认删除选中的未版本项？此操作会直接删除本地文件，不能通过 SVN 还原。",
            isPresented: $confirmDeleteUnversioned,
            titleVisibility: .visible
        ) {
            Button("删除未版本项", role: .destructive) {
                Task { await runDeleteUnversioned() }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "将选中冲突路径标记为已解决（svn resolve --accept working）？树冲突建议在冲突工作区专用面板处理。",
            isPresented: $confirmMarkResolved,
            titleVisibility: .visible
        ) {
            Button("标记已解决") {
                Task { await runMarkResolved() }
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showAddSheet) {
            addSheet
        }
        .sheet(isPresented: $showDeleteUnversionedSheet) {
            deleteUnversionedSheet
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
        .sheet(isPresented: $showCaseConflictRepairSheet) {
            caseConflictRepairSheet
        }
        .sheet(isPresented: $showIgnoreSheet) {
            ignoreSheet
        }
        .sheet(isPresented: $showCopyMoveSheet) {
            copyMoveSheet
        }
        .sheet(isPresented: $showUpdateToRevisionSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("更新到修订（svn update -r）")
                    .font(.headline)
                TextField("修订号（留空=HEAD）", text: $updateToRevisionText)
                Picker("深度（--set-depth，可选）", selection: $setDepth) {
                    Text("empty").tag(SvnDepth.empty)
                    Text("files").tag(SvnDepth.files)
                    Text("immediates").tag(SvnDepth.immediates)
                    Text("infinity").tag(SvnDepth.infinity)
                }
                .pickerStyle(.radioGroup)
                Toggle("忽略外部项（--ignore-externals）", isOn: $updateIgnoreExternals)
                Text("将作用于选中路径；未选中时作用于 WC 根。指定修订时不再自动钉 HEAD。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("取消") { showUpdateToRevisionSheet = false }
                    Spacer()
                    Button("更新") {
                        showUpdateToRevisionSheet = false
                        Task { await runUpdateToRevision() }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 440)
        }
        .sheet(isPresented: $showChangelistSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("管理变更列表")
                    .font(.headline)
                Picker("操作", selection: $changelistOperation) {
                    ForEach(ChangelistOperation.allCases) { operation in
                        Text(operation.rawValue).tag(operation)
                    }
                }
                .pickerStyle(.segmented)
                if changelistOperation == .assign {
                    TextField("列表名称", text: $changelistName)
                    let names = changesVM.map {
                        ChangelistPolicy.groups(from: $0.entries).compactMap(\.name)
                    } ?? []
                    if !names.isEmpty {
                        Picker("现有列表", selection: $changelistName) {
                            Text("输入新名称").tag("")
                            ForEach(names, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                }
                Picker("目录深度", selection: $changelistDepth) {
                    Text("仅所选项").tag(SvnDepth.empty)
                    Text("文件").tag(SvnDepth.files)
                    Text("直接子项").tag(SvnDepth.immediates)
                    Text("递归").tag(SvnDepth.infinity)
                }
                HStack {
                    Button("取消") { showChangelistSheet = false }
                    Spacer()
                    Button("应用") { Task { await runChangelistOperation() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            selectedPaths.isEmpty
                                || (changelistOperation == .assign
                                    && changelistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        )
                }
            }
            .padding(24)
            .frame(width: 440)
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
                Text("列表").tag(ChangesDisplayMode.changelists)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 210)
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

            Menu {
                Button("删除", role: .destructive) {
                    confirmDelete = true
                }
                .disabled(selectedPaths.isEmpty)
                Button("删除（保留本地）", role: .destructive) {
                    confirmDeleteKeepLocal = true
                }
                .disabled(selectedPaths.isEmpty)
                Button("删除未版本项", role: .destructive) {
                    Task { await prepareUnversionedDeletion() }
                }
            } label: {
                Label("删除", systemImage: "trash")
            }
            .disabled(actionsVM == nil || actionsVM?.isRunning == true)

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

            Button("修复大小写…") {
                prepareCaseConflictRepairSheet()
                showCaseConflictRepairSheet = true
            }
            .disabled(selectedPaths.count != 1 || actionsVM?.isRunning == true)

            Button("复制/移动…") {
                prepareCopyMoveSheet()
                showCopyMoveSheet = true
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

            Button("更新到修订…") {
                updateToRevisionText = ""
                updateIgnoreExternals = false
                setDepth = .infinity
                showUpdateToRevisionSheet = true
            }
            .disabled(actionsVM == nil || actionsVM?.isRunning == true)

            Button("忽略选中…") {
                ignoreKind = .exactFilename
                showIgnoreSheet = true
            }
            .disabled(selectedPaths.isEmpty || session == nil || actionsVM?.isRunning == true)

            Button("变更列表…") {
                prepareChangelistSheet()
            }
            .disabled(selectedPaths.isEmpty || changesVM == nil || actionsVM?.isRunning == true)

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
                    } else if displayMode == .tree {
                        OutlineGroup(changesVM.visibleTreeEntries, children: \.outlineChildren) { node in
                            treeRow(node)
                                .tag(node.path)
                                .listRowBackground(
                                    node.fileStatus.map { highlightColor(changesVM.highlight(for: $0)) } ?? Color.clear
                                )
                        }
                    } else {
                        ForEach(changesVM.visibleChangelistGroups) { group in
                            Section(group.displayName) {
                                ForEach(group.entries, id: \.path) { entry in
                                    flatRow(entry)
                                        .tag(entry.path)
                                        .listRowBackground(highlightColor(changesVM.highlight(for: entry)))
                                }
                            }
                        }
                    }
                }
                .contextMenu {
                    ForEach(SvnCommandCatalog.dailyCFMCommands, id: \.id) { descriptor in
                        catalogContextButton(descriptor)
                    }
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func catalogContextButton(_ descriptor: SvnCommandDescriptor) -> some View {
        switch descriptor.id {
        case .repairMoveCopy:
            Button("修复移动") {
                Task { await runRepairMove() }
            }
            .disabled(!canRepairMove)
            Button("修复复制") {
                Task { await runRepairCopy() }
            }
            .disabled(!canRepairCopy)
        case .repairFilenameCaseConflict:
            Button("修复文件名大小写…") {
                prepareCaseConflictRepairSheet()
                showCaseConflictRepairSheet = true
            }
            .disabled(selectedPaths.count != 1 || actionsVM?.isRunning == true)
        case .changeLists:
            Button("变更列表…") { prepareChangelistSheet() }
                .disabled(selectedPaths.isEmpty || actionsVM?.isRunning == true)
        default:
            Button(menuTitle(for: descriptor)) {
                handleCatalogCommand(descriptor.id)
            }
            .disabled(!isCatalogCommandEnabled(descriptor.id))
        }
    }

    private func menuTitle(for descriptor: SvnCommandDescriptor) -> String {
        switch descriptor.id {
        case .rename, .copyMove, .addToIgnoreList, .add, .cleanup, .revert, .compareRevisions:
            return "\(descriptor.displayName)…"
        case .resolved:
            return "\(descriptor.displayName)…"
        case .getLock, .breakLock:
            return "\(descriptor.displayName)…"
        default:
            return descriptor.displayName
        }
    }

    private func isCatalogCommandEnabled(_ id: SvnCommandID) -> Bool {
        switch id {
        case .update, .cleanup, .checkForModifications, .updateToRevision:
            return actionsVM != nil && actionsVM?.isRunning != true
        case .add:
            return changesVM != nil && actionsVM?.isRunning != true
        case .commit, .diff, .showLog, .editConflicts:
            return true
        case .diffWithURL:
            return selectedPaths.count == 1 && actionsVM?.isRunning != true
        case .compareRevisions:
            return selectedPaths.count == 1 && actionsVM?.isRunning != true
        case .resolved:
            return !selectedMarkResolvedPaths.isEmpty && actionsVM?.isRunning != true
        case .getLock, .releaseLock, .breakLock:
            return !selectedPaths.isEmpty && actionsVM?.isRunning != true
        case .delete, .revert, .addToIgnoreList:
            return !selectedPaths.isEmpty && actionsVM?.isRunning != true
                && (id != .addToIgnoreList || session != nil)
        case .deleteKeepLocal:
            return !selectedPaths.isEmpty && actionsVM?.isRunning != true
        case .deleteUnversioned:
            return changesVM != nil && actionsVM?.isRunning != true
        case .rename, .copyMove, .repairFilenameCaseConflict:
            return selectedPaths.count == 1 && actionsVM?.isRunning != true
        case .changeLists:
            return !selectedPaths.isEmpty && actionsVM?.isRunning != true
        default:
            return actionsVM?.isRunning != true
        }
    }

    /// 当前选中中处于冲突状态的路径（保持 CFM 可见列表顺序，非字母序）。
    private var selectedConflictedPaths: [String] {
        guard let changesVM else { return [] }
        let selected = selectedPaths
        return changesVM.visibleFlatEntries
            .filter { selected.contains($0.path) && ($0.itemStatus == .conflicted || $0.isTreeConflict) }
            .map(\.path)
    }

    /// 多选时取列表可见顺序中的首个冲突路径。
    private var primarySelectedConflictedPath: String? {
        selectedConflictedPaths.first
    }

    /// 可批量「标记已解决」的选中路径（排除树冲突；保持可见列表顺序）。
    private var selectedMarkResolvedPaths: [String] {
        guard let changesVM else { return [] }
        let selected = selectedPaths
        return changesVM.visibleFlatEntries
            .filter {
                selected.contains($0.path)
                    && ConflictResolveBatchPolicy.isEligibleForMarkResolved(
                        itemStatus: $0.itemStatus,
                        isTreeConflict: $0.isTreeConflict
                    )
            }
            .map(\.path)
    }

    private func handleCatalogCommand(_ id: SvnCommandID) {
        switch id {
        case .update:
            Task { await runUpdate() }
        case .updateToRevision:
            updateToRevisionText = ""
            updateIgnoreExternals = false
            setDepth = .infinity
            showUpdateToRevisionSheet = true
        case .add:
            prepareAddSheet()
            showAddSheet = true
        case .delete:
            confirmDelete = true
        case .deleteKeepLocal:
            confirmDeleteKeepLocal = true
        case .deleteUnversioned:
            Task { await prepareUnversionedDeletion() }
        case .revert:
            revertRecursive = false
            showRevertSheet = true
        case .cleanup:
            cleanupOptions = .default
            showCleanupSheet = true
        case .rename:
            prepareRenameSheet()
            showRenameSheet = true
        case .repairFilenameCaseConflict:
            prepareCaseConflictRepairSheet()
            showCaseConflictRepairSheet = true
        case .addToIgnoreList:
            ignoreKind = .exactFilename
            showIgnoreSheet = true
        case .copyMove:
            prepareCopyMoveSheet()
            showCopyMoveSheet = true
        case .changeLists:
            prepareChangelistSheet()
        case .commit, .diff, .showLog, .checkForModifications:
            _ = navigator?.perform(command: id, paths: Array(selectedPaths).sorted())
        case .editConflicts:
            if let first = primarySelectedConflictedPath {
                navigator?.pendingConflictPath = first
            }
            navigator?.selectMode(.conflicts)
            navigator?.lastAutomationMessage = primarySelectedConflictedPath.map { "编辑冲突：\($0)" }
                ?? "打开冲突工作区"
        case .resolved:
            confirmMarkResolved = true
        case .getLock, .releaseLock, .breakLock:
            _ = navigator?.perform(command: id, paths: Array(selectedPaths).sorted())
        default:
            _ = navigator?.perform(command: id, paths: Array(selectedPaths).sorted())
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
                case .changelist:
                    Text(entry.changelist ?? "—")
                        .font(.caption)
                        .foregroundStyle(
                            ChangelistPolicy.isIgnoredOnCommit(entry.changelist) ? .orange : .secondary
                        )
                        .frame(width: 110, alignment: .leading)
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
        consumePendingCopyMoveIntentIfReady()
    }

    private func consumePendingCopyMoveIntentIfReady() {
        guard let intent = navigator?.pendingCopyMoveIntent,
              let record = workspaceController.selectedRecord,
              record.isValid,
              let relativePaths = intent.relativePaths(under: record.localPath),
              relativePaths.count == 1 else { return }
        selectedPaths = Set(relativePaths)
        onFocusedPathChange?(relativePaths[0])
        prepareCopyMoveSheet()
        showCopyMoveSheet = true
        _ = navigator?.consumePendingCopyMoveIntent()
    }

    /// 关闭 Add/Cleanup/Revert/Delete 等对话框并清空临时勾选，防止跨 WC 误操作。
    private func dismissActionSheets() {
        showAddSheet = false
        showCleanupSheet = false
        showRevertSheet = false
        showRenameSheet = false
        showCaseConflictRepairSheet = false
        showIgnoreSheet = false
        showCopyMoveSheet = false
        showChangelistSheet = false
        confirmDelete = false
        confirmRevert = false
        confirmMarkResolved = false
        addSelectedPaths = []
        renameNewName = ""
        caseConflictNewName = ""
        ignoreKind = .exactFilename
        copyMoveKind = .move
        copyMoveDestination = ""
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

    private func consumePendingChangelistIntent() {
        guard let intent = navigator?.consumePendingChangelistIntent() else { return }
        if !intent.paths.isEmpty {
            selectedPaths = Set(intent.paths)
            prepareChangelistSheet()
        } else {
            statusBanner = "请选择路径后使用“变更列表…”管理归属"
        }
    }

    private func consumePendingDeleteIntent() {
        guard actionsVM != nil else { return }
        guard let intent = navigator?.consumePendingDeleteIntent() else { return }
        selectedPaths = Set(intent.paths)
        switch intent.command {
        case .deleteKeepLocal:
            confirmDeleteKeepLocal = true
        case .deleteUnversioned:
            Task { await prepareUnversionedDeletion() }
        default:
            break
        }
    }

    private func prepareChangelistSheet() {
        let selectedEntries = changesVM?.entries.filter { selectedPaths.contains($0.path) } ?? []
        let existingNames = Set(selectedEntries.compactMap(\.changelist))
        changelistName = existingNames.count == 1 ? existingNames.first ?? "" : ""
        changelistOperation = .assign
        changelistDepth = .empty
        showChangelistSheet = true
    }

    private func runChangelistOperation() async {
        guard let record = workspaceController.selectedRecord,
              let changesVM else { return }
        let wc = URL(fileURLWithPath: record.localPath)
        let paths = Array(selectedPaths).sorted()
        do {
            switch changelistOperation {
            case .assign:
                try await svnService.assignChangelist(
                    wc: wc,
                    name: changelistName,
                    paths: paths,
                    depth: changelistDepth
                )
                statusBanner = "已将 \(paths.count) 项移动到变更列表 \(changelistName.trimmingCharacters(in: .whitespacesAndNewlines))"
            case .remove:
                try await svnService.removeFromChangelists(
                    wc: wc,
                    paths: paths,
                    depth: changelistDepth
                )
                statusBanner = "已将 \(paths.count) 项移出变更列表"
            }
            showChangelistSheet = false
            displayMode = .changelists
            changesVM.displayMode = .changelists
            await changesVM.refresh()
        } catch {
            statusBanner = "变更列表操作失败：\(error.localizedDescription)"
        }
    }

    private func runUpdate() async {
        guard let actionsVM, let changesVM else { return }
        // 有多选时按选中路径更新（≥2 时 Service 层会钉住 HEAD 防 mixed-rev）
        await actionsVM.update(paths: Array(selectedPaths))
        await syncAfterAction(actionsVM, changesVM)
    }

    private func runUpdateToRevision() async {
        guard let actionsVM, let changesVM else { return }
        let paths = Array(selectedPaths)
        let trimmed = updateToRevisionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let revision: Revision?
        if trimmed.isEmpty {
            revision = nil
        } else if let value = Int(trimmed), value > 0 {
            revision = Revision(value)
        } else {
            statusBanner = "修订号无效：\(trimmed)"
            return
        }
        // infinity 表示不改 depth（仅 -r / ignore-externals）；其它值传 --set-depth
        let depthArg: SvnDepth? = setDepth == .infinity ? nil : setDepth
        await actionsVM.update(
            paths: paths,
            revision: revision,
            setDepth: depthArg,
            ignoreExternals: updateIgnoreExternals
        )
        await syncAfterAction(actionsVM, changesVM)
        if case .updateCompleted(let summary) = actionsVM.state {
            let shouldClose = await shouldAutoCloseProgress(
                outcome: progressOutcome(for: summary),
                isLocalOperation: false
            )
            if !shouldClose {
                let revLabel = revision.map { "r\($0.value)" } ?? "HEAD"
                statusBanner = "已更新到 \(revLabel)"
            }
        }
    }

    private func runSetDepth() async {
        guard let actionsVM, let changesVM else { return }
        let paths = Array(selectedPaths)
        await actionsVM.update(paths: paths, setDepth: setDepth)
        await syncAfterAction(actionsVM, changesVM)
        if case .updateCompleted(let summary) = actionsVM.state {
            let shouldClose = await shouldAutoCloseProgress(
                outcome: progressOutcome(for: summary),
                isLocalOperation: true
            )
            if !shouldClose {
                statusBanner = "已设置深度 \(String(describing: setDepth))"
            }
        }
    }

    /// 将选中路径按文件名或扩展名通配追加到父目录 `svn:ignore`（#32）。
    private func ignoreSelected() async {
        guard let session, let record = workspaceController.selectedRecord, let changesVM else { return }
        let paths = Array(selectedPaths).sorted()
        let plans = IgnorePatternPolicy.plans(relativePaths: paths, kind: ignoreKind)
        guard !plans.isEmpty else {
            statusBanner = ignoreKind == .extensionWildcard
                ? "选中项无法生成扩展名通配（无扩展名或隐藏文件）"
                : "没有可忽略的路径"
            return
        }

        let wc = URL(fileURLWithPath: record.localPath)
        do {
            for plan in plans {
                let existing = try await session.svnService.propertyValue(
                    wc: wc,
                    target: plan.target,
                    name: "svn:ignore"
                )
                let value = IgnorePatternPolicy.mergeIgnoreProperty(
                    existing: existing?.value,
                    patterns: plan.patterns
                )
                let vm = PropertyViewModel(workingCopy: wc, target: plan.target, provider: session.svnService)
                await vm.load()
                await vm.save(name: "svn:ignore", value: value)
            }
            let preview = plans.flatMap(\.patterns).joined(separator: ", ")
            statusBanner = "已写入 svn:ignore：\(preview)"
            await refreshAfterMutation(changesVM)
            selectedPaths = []
        } catch {
            statusBanner = "忽略失败：\(error.localizedDescription)"
        }
    }

    private var ignoreSheet: some View {
        let plans = IgnorePatternPolicy.plans(
            relativePaths: Array(selectedPaths),
            kind: ignoreKind
        )
        return VStack(alignment: .leading, spacing: 14) {
            Text("添加到忽略列表")
                .font(.headline)
            Picker("模式", selection: $ignoreKind) {
                ForEach(IgnorePatternKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.radioGroup)
            if plans.isEmpty {
                Text("当前选择无法生成忽略模式。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("将写入：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(plans, id: \.target) { plan in
                    Text("\(plan.target)：\(plan.patterns.joined(separator: ", "))")
                        .font(.caption.monospaced())
                }
            }
            Text("写入各父目录的 svn:ignore（非 global-ignores，后者见设置 T5）。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("取消") { showIgnoreSheet = false }
                Spacer()
                Button("写入忽略") {
                    showIgnoreSheet = false
                    Task { await ignoreSelected() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(plans.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
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

    private func runDeleteKeepingLocal() async {
        guard let actionsVM, let changesVM else { return }
        await actionsVM.deleteKeepingLocal(paths: Array(selectedPaths).sorted())
        await syncAfterAction(actionsVM, changesVM)
    }

    private func prepareUnversionedDeletion() async {
        guard let actionsVM else { return }
        let candidates = await actionsVM.prepareUnversionedDeletion()
        guard !candidates.isEmpty else {
            statusBanner = "当前没有可删除的未版本项"
            return
        }
        unversionedDeletionCandidates = candidates
        let candidatePaths = Set(candidates.map(\.path))
        let selected = selectedPaths.intersection(candidatePaths)
        unversionedDeletionSelectedPaths = selected.isEmpty ? candidatePaths : selected
        showDeleteUnversionedSheet = true
    }

    private func runDeleteUnversioned() async {
        guard let actionsVM, let changesVM else { return }
        let paths = Array(unversionedDeletionSelectedPaths).sorted()
        guard !paths.isEmpty else {
            statusBanner = "未勾选未版本项"
            return
        }
        showDeleteUnversionedSheet = false
        await actionsVM.deleteUnversioned(paths: paths)
        await syncAfterAction(actionsVM, changesVM)
    }

    private var deleteUnversionedSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("删除未版本项")
                .font(.headline)
            List(unversionedDeletionCandidates, id: \.path) { entry in
                Toggle(isOn: Binding(
                    get: { unversionedDeletionSelectedPaths.contains(entry.path) },
                    set: { selected in
                        if selected {
                            unversionedDeletionSelectedPaths.insert(entry.path)
                        } else {
                            unversionedDeletionSelectedPaths.remove(entry.path)
                        }
                    }
                )) {
                    Text(entry.path)
                        .font(.body.monospaced())
                }
            }
            HStack {
                Button("取消") { showDeleteUnversionedSheet = false }
                Spacer()
                Button("继续") {
                    showDeleteUnversionedSheet = false
                    confirmDeleteUnversioned = true
                }
                .keyboardShortcut(.defaultAction)
                .disabled(unversionedDeletionSelectedPaths.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460, height: 360)
    }

    /// CFM「标记为已解决」：对选中文本/属性冲突执行 `svn resolve --accept working`。
    private func runMarkResolved() async {
        guard let changesVM, let record = workspaceController.selectedRecord else { return }
        let paths = selectedMarkResolvedPaths
        guard !paths.isEmpty else {
            statusBanner = "无可用路径：树冲突请在冲突工作区处理"
            return
        }
        let wc = URL(fileURLWithPath: record.localPath)
        var succeeded: [String] = []
        var failures: [String] = []
        for path in paths {
            do {
                try await svnService.resolve(wc: wc, path: path, accept: .working)
                succeeded.append(path)
            } catch {
                failures.append("\(path): \(error.localizedDescription)")
            }
        }
        if failures.isEmpty {
            statusBanner = "已标记 \(succeeded.count) 项为已解决"
        } else if succeeded.isEmpty {
            statusBanner = "标记已解决失败：\(failures.joined(separator: "; "))"
        } else {
            statusBanner = "部分成功 \(succeeded.count)/\(paths.count)：\(failures.joined(separator: "; "))"
        }
        navigator?.lastAutomationMessage = statusBanner
        await changesVM.refresh()
        selectedPaths = selectedPaths.subtracting(succeeded)
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

    private var caseConflictRepairSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("修复文件名大小写冲突")
                .font(.headline)
            if let source = selectedPaths.sorted().first {
                Text("当前：\(source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("修复后的名称", text: $caseConflictNewName)
                Text("仅支持同一目录、仅大小写不同的名称。应用会通过临时 SVN 改名完成修复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("取消") { showCaseConflictRepairSheet = false }
                Spacer()
                Button("修复") {
                    Task { await runCaseConflictRepairFromSheet() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    selectedPaths.count != 1
                        || caseConflictNewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func prepareRenameSheet() {
        guard let path = selectedPaths.sorted().first else {
            renameNewName = ""
            return
        }
        renameNewName = (path as NSString).lastPathComponent
    }

    private func prepareCaseConflictRepairSheet() {
        guard let path = selectedPaths.sorted().first else {
            caseConflictNewName = ""
            return
        }
        caseConflictNewName = (path as NSString).lastPathComponent
    }

    private func runCaseConflictRepairFromSheet() async {
        guard let actionsVM, let changesVM else { return }
        guard let source = selectedPaths.sorted().first, selectedPaths.count == 1 else {
            statusBanner = "请先选中恰好一项再修复文件名大小写"
            showCaseConflictRepairSheet = false
            return
        }
        let existing = Set(changesVM.entries.map(\.path))
        showCaseConflictRepairSheet = false
        await actionsVM.repairFilenameCaseConflict(
            sourcePath: source,
            newName: caseConflictNewName,
            existingPaths: existing
        )
        await syncAfterAction(actionsVM, changesVM)
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

    private var copyMoveSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("复制 / 移动")
                .font(.headline)
            if let source = selectedPaths.sorted().first {
                Text("源：\(source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("操作", selection: $copyMoveKind) {
                    ForEach(CopyMoveKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                TextField("目标相对路径", text: $copyMoveDestination)
                Text("目标须在工作副本内；同目录改名请用「重命名」。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("取消") { showCopyMoveSheet = false }
                Spacer()
                Button(copyMoveKind.displayName) {
                    Task { await runCopyMoveFromSheet() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    selectedPaths.count != 1
                        || copyMoveDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func prepareCopyMoveSheet() {
        copyMoveKind = .move
        guard let path = selectedPaths.sorted().first else {
            copyMoveDestination = ""
            return
        }
        let parent = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        let suggested = "\(name)-copy"
        if parent.isEmpty || parent == "." {
            copyMoveDestination = suggested
        } else {
            copyMoveDestination = (parent as NSString).appendingPathComponent(suggested)
        }
    }

    private func runCopyMoveFromSheet() async {
        guard let actionsVM, let changesVM else { return }
        guard let source = selectedPaths.sorted().first, selectedPaths.count == 1 else {
            statusBanner = "请先选中恰好一项再复制/移动"
            showCopyMoveSheet = false
            return
        }
        let existing = Set(changesVM.entries.map(\.path))
        showCopyMoveSheet = false
        await actionsVM.copyMove(
            kind: copyMoveKind,
            sourcePath: source,
            destinationPath: copyMoveDestination,
            existingPaths: existing
        )
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
            let shouldClose = await shouldAutoCloseProgress(
                outcome: progressOutcome(for: summary),
                isLocalOperation: false
            )
            statusBanner = shouldClose
                ? nil
                : "更新完成：更新 \(summary.updated) / 新增 \(summary.added) / 删除 \(summary.deleted) / 冲突 \(summary.conflicted)"
            await refreshAfterMutation(changesVM)
            selectedPaths = []
            if summary.conflicted > 0 {
                navigator?.selectMode(.conflicts)
                navigator?.lastAutomationMessage = "更新产生 \(summary.conflicted) 个冲突，已切换到冲突工作区"
            }
        case .completed(let op):
            let shouldClose = await shouldAutoCloseProgress(
                outcome: .successful,
                isLocalOperation: true
            )
            statusBanner = shouldClose ? nil : "\(label(for: op)) 完成"
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

    private func shouldAutoCloseProgress(
        outcome: ProgressOperationOutcome,
        isLocalOperation: Bool
    ) async -> Bool {
        guard let session else { return false }
        let mode = await session.settingsStore.settings().progressAutoCloseMode
        return ProgressAutoClosePolicy.shouldClose(
            mode: mode,
            outcome: outcome,
            isLocalOperation: isLocalOperation
        )
    }

    private func progressOutcome(for summary: UpdateSummary) -> ProgressOperationOutcome {
        ProgressOperationOutcome(
            hasErrors: false,
            hasConflicts: summary.conflicted > 0,
            hasMerges: summary.merged > 0 || summary.added > 0 || summary.deleted > 0
        )
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
        case .deleteKeepLocal: return "删除（保留本地）"
        case .deleteUnversioned: return "删除未版本项"
        case .rename: return "重命名"
        case .copy: return "复制"
        case .move: return "移动"
        case .repairMove: return "修复移动"
        case .repairCopy: return "修复复制"
        case .repairFilenameCaseConflict: return "修复文件名大小写"
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
