import SwiftUI
import AppKit
import MacSvnCore

/// 历史页：左侧修订列表，右侧详情（说明 / 变更路径 / 操作）。
///
/// T2.2：过滤 / stop-on-copy / Next·All / Actions。
/// 变更路径右键 L01–L14。
public struct MacSvnLogView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession

    @State private var viewModel: LogViewModel?
    @State private var errorText: String?
    @State private var authorFilter = ""
    @State private var messageFilter = ""
    @State private var pathFilter = ""
    @State private var stopOnCopy = false
    @State private var offlineMode = false
    @State private var statusText: String?
    @State private var selectedRevision: Int?
    /// 当前 WC 的 `svn info` URL，供路径归一化与 Browse。
    @State private var workingCopyURL: String = ""
    @State private var repositoryRoot: String = ""
    @State private var unifiedDiffText: String?
    @State private var showUnifiedDiffSheet = false

    @State private var revisionPropertyViewModel: RevisionPropertyViewModel?
    @State private var showRevisionPropertySheet = false
    @State private var revisionPropertyEditMode = false
    @State private var revisionAuthor = ""
    @State private var revisionMessage = ""
    @State private var showStatisticsSheet = false

    // T2.4 对话框状态
    @State private var showBranchSheet = false
    @State private var branchSourcePegURL = ""
    @State private var branchRevision: Revision = Revision(0)
    @State private var branchName = ""
    @State private var branchMessage = "create branch from log"
    @State private var branchKind: BranchReferenceKind = .branch

    @State private var showCheckoutExportSheet = false
    @State private var checkoutExportPegURL = ""
    @State private var checkoutExportRevision: Revision = Revision(0)
    @State private var checkoutExportIsExport = false

    @State private var pendingConfirmTitle = ""
    @State private var pendingConfirmDetail = ""
    @State private var pendingConfirmAction: (() async -> Void)?
    @State private var showConfirmSheet = false

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
            logToolbar
            logFilterBar

            if let statusText {
                Text(statusText).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red).padding(.horizontal, 16)
            }

            content
        }
        .onChange(of: workspaceController.selectedID) { _, _ in
            selectedRevision = nil
            Task { await reload() }
        }
        .onChange(of: navigator.pendingRevisionGraphLog) { _, _ in
            Task { await reload() }
        }
        .onChange(of: navigator.pendingRevisionPropertiesIntent) { _, _ in
            Task { await consumePendingRevisionPropertiesIntent() }
        }
        .task { await reload() }
        .sheet(isPresented: $showUnifiedDiffSheet) {
            NavigationStack {
                ScrollView {
                    Text(unifiedDiffText ?? "")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("统一 Diff")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { showUnifiedDiffSheet = false }
                    }
                }
            }
            .frame(minWidth: 640, minHeight: 420)
        }
        .sheet(isPresented: $showBranchSheet) {
            branchSheet
        }
        .sheet(isPresented: $showCheckoutExportSheet) {
            checkoutExportSheet
        }
        .sheet(isPresented: $showConfirmSheet) {
            confirmSheet
        }
        .sheet(isPresented: $showRevisionPropertySheet) {
            revisionPropertySheet
        }
        .sheet(isPresented: $showStatisticsSheet) {
            statisticsSheet
        }
    }

    @ViewBuilder
    private var logToolbar: some View {
        HStack {
            Text("历史").font(.title2.weight(.semibold))
            Spacer()
            Button("AI Release Notes") {
                guard let viewModel else { return }
                let entries = filteredEntries(viewModel.entries)
                navigator.pendingReleaseNotesEntries = entries
                navigator.selectRoute(.releaseNotes)
                navigator.lastAutomationMessage = "从历史带入 \(entries.count) 条生成 Release Notes"
            }
            .disabled(viewModel == nil || (viewModel?.entries.isEmpty ?? true))
            Button("刷新") { Task { await reload() } }
            Button("Next") { Task { await viewModel?.loadMore() } }
                .disabled(viewModel?.hasMore != true || viewModel?.isLoading == true)
                .help("再加载一批（Tortoise Next）")
            Button("Show All") { Task { await viewModel?.loadAll() } }
                .disabled(viewModel?.hasMore != true || viewModel?.isLoading == true)
                .help("循环拉取直至无更多（Tortoise Show All）")
            Button("统计") { showStatisticsSheet = true }
                .disabled(viewModel?.entries.isEmpty != false)
        }
        .padding(16)
    }

    @ViewBuilder
    private var logFilterBar: some View {
        HStack(spacing: 8) {
            TextField("作者过滤", text: $authorFilter)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 140)
            TextField("说明关键字", text: $messageFilter)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 180)
            TextField("路径过滤", text: $pathFilter)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
            Toggle("Stop on copy", isOn: $stopOnCopy)
                .toggleStyle(.checkbox)
                .help("svn log --stop-on-copy：在分支拷贝点停止")
                .onChange(of: stopOnCopy) { _, newValue in
                    Task { await applyStopOnCopy(newValue) }
                }
            Toggle("离线", isOn: $offlineMode)
                .toggleStyle(.checkbox)
                .help("只读取已缓存日志，不访问仓库")
                .onChange(of: offlineMode) { _, _ in
                    Task { await reload() }
                }
            if let viewModel, viewModel.state == .loaded || viewModel.state == .loadingMore {
                let shown = filteredEntries(viewModel.entries).count
                Text("显示 \(shown) / 已载 \(viewModel.entries.count)")
                    .font(.caption).foregroundStyle(.secondary)
                if !pathFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   shown == 0, !viewModel.entries.isEmpty {
                    Text("路径过滤无命中（需 verbose 路径明细）")
                        .font(.caption2).foregroundStyle(.orange)
                }
                Text(logDataSourceLabel(viewModel.dataSource))
                    .font(.caption2)
                    .foregroundStyle(viewModel.dataSource == .live ? Color.secondary : Color.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if workspaceController.selectedRecord == nil {
            ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
        } else if let viewModel {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("加载日志…").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                ContentUnavailableView("失败", systemImage: "exclamationmark.triangle", description: Text(message))
            case .loaded, .loadingMore:
                let entries = filteredEntries(viewModel.entries)
                HStack(spacing: 0) {
                    List(selection: $selectedRevision) {
                        ForEach(entries, id: \.revision.value) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(LogActionsSummary.symbols(for: entry.changedPaths))
                                    .font(.caption.monospaced().weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .leading)
                                    .accessibilityLabel("Actions \(LogActionsSummary.symbols(for: entry.changedPaths))")
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("r\(entry.revision.value)")
                                            .font(.headline.monospaced())
                                        Text(entry.author.isEmpty ? "unknown" : entry.author)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Text(entry.message)
                                        .font(.caption)
                                        .lineLimit(2)
                                    Text(entry.date?.formatted() ?? "")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .tag(entry.revision.value)
                            .padding(.vertical, 2)
                            .contextMenu {
                                if let first = entry.changedPaths.first {
                                    logPathContextMenu(path: first.path, revision: entry.revision)
                                }
                                Divider()
                                logRevisionContextMenu(path: entry.changedPaths.first?.path ?? "", revision: entry.revision)
                                Divider()
                                logClipboardContextMenu(entry: entry)
                            }
                        }
                    }
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)

                    Divider()

                    detailPane(entries: entries)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if viewModel.state == .loadingMore {
                    ProgressView().padding()
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func detailPane(entries: [LogEntry]) -> some View {
        if let selectedRevision,
           let entry = entries.first(where: { $0.revision.value == selectedRevision }) {
            ScrollView {
                detailContent(entry: entry)
                    .padding(20)
            }
        } else {
            ContentUnavailableView(
                "选择一条修订",
                systemImage: "clock.arrow.circlepath",
                description: Text("在左侧点击某次提交，查看说明与变更文件详情")
            )
        }
    }

    @ViewBuilder
    private func detailContent(entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            detailHeader(entry: entry)
            LabeledContent("作者", value: entry.author.isEmpty ? "unknown" : entry.author)
            detailMessage(entry: entry)
            detailChangedPaths(entry: entry)
            detailActions(entry: entry)
        }
    }

    @ViewBuilder
    private func detailHeader(entry: LogEntry) -> some View {
        HStack {
            Text("r\(entry.revision.value)")
                .font(.title2.monospaced().weight(.semibold))
            let actions = LogActionsSummary.symbols(for: entry.changedPaths)
            if !actions.isEmpty {
                Text(actions)
                    .font(.title3.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.date?.formatted() ?? "")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func detailMessage(entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("提交说明")
                .font(.headline)
            Text(entry.message.isEmpty ? "（无说明）" : entry.message)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func detailChangedPaths(entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("变更路径（\(entry.changedPaths.count)）")
                .font(.headline)
            if entry.changedPaths.isEmpty {
                Text("此批次未带路径明细（可刷新或加载 verbose 日志）")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(entry.changedPaths.enumerated()), id: \.offset) { _, change in
                    changedPathRow(change: change, entry: entry)
                }
            }
        }
    }

    @ViewBuilder
    private func changedPathRow(change: ChangedPath, entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(change.action.rawValue)
                .font(.caption.monospaced())
                .frame(width: 16, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(change.path)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            Button("Diff") {
                Task {
                    await performLogAction(
                        .logCompareWithPrevious,
                        changedPath: change.path,
                        revision: entry.revision
                    )
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
        .contextMenu {
            logPathContextMenu(path: change.path, revision: entry.revision)
            Divider()
            logRevisionContextMenu(path: change.path, revision: entry.revision)
            Divider()
            logClipboardContextMenu(entry: entry)
        }
    }

    @ViewBuilder
    private func detailActions(entry: LogEntry) -> some View {
        HStack {
            Button("在变更区查看 Diff") {
                guard let first = entry.changedPaths.first?.path else { return }
                Task {
                    await performLogAction(
                        .logCompareWithPrevious,
                        changedPath: first,
                        revision: entry.revision
                    )
                }
            }
            .disabled(entry.changedPaths.isEmpty)
            Button("更新到此版本") {
                Task { await updateTo(entry.revision) }
            }
            Button("修订属性") {
                Task { await openRevisionProperties(revision: entry.revision, edit: false) }
            }
            Button("编辑作者 / 说明") {
                Task { await openRevisionProperties(revision: entry.revision, edit: true) }
            }
            Button("复制摘要") {
                copyLogEntryToClipboard(entry)
            }
        }
    }

    @ViewBuilder
    private func logPathContextMenu(path: String, revision: Revision) -> some View {
        ForEach(LogContextActionPolicy.t2FileActionIDs, id: \.rawValue) { command in
            Button(SvnCommandCatalog.descriptor(for: command)?.displayName ?? command.rawValue) {
                Task { await performLogAction(command, changedPath: path, revision: revision) }
            }
        }
        Divider()
        ForEach(LogContextActionPolicy.t3RevisionActionIDs, id: \.rawValue) { command in
            Button(SvnCommandCatalog.descriptor(for: command)?.displayName ?? command.rawValue) {
                Task { await performLogAction(command, changedPath: path, revision: revision) }
            }
        }
    }

    @ViewBuilder
    private func logRevisionContextMenu(path: String, revision: Revision) -> some View {
        ForEach(LogContextActionPolicy.t2RevisionActionIDs, id: \.rawValue) { command in
            Button(SvnCommandCatalog.descriptor(for: command)?.displayName ?? command.rawValue) {
                Task { await performLogAction(command, changedPath: path, revision: revision) }
            }
        }
        Divider()
        ForEach(LogContextActionPolicy.t3RevisionPropertyActionIDs, id: \.rawValue) { command in
            Button(SvnCommandCatalog.descriptor(for: command)?.displayName ?? command.rawValue) {
                Task { await performLogAction(command, changedPath: path, revision: revision) }
            }
        }
    }

    @ViewBuilder
    private func logClipboardContextMenu(entry: LogEntry) -> some View {
        ForEach(LogContextActionPolicy.t2ClipboardActionIDs, id: \.rawValue) { command in
            Button(SvnCommandCatalog.descriptor(for: command)?.displayName ?? command.rawValue) {
                copyLogEntryToClipboard(entry)
            }
        }
    }

    private func copyLogEntryToClipboard(_ entry: LogEntry) {
        let text = LogClipboardSummary.text(for: entry)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusText = "已复制 r\(entry.revision.value) 摘要到剪贴板"
        navigator.lastAutomationMessage = statusText
    }

    private var branchSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("从 r\(branchRevision.value) 创建分支/标签")
                .font(.headline)
            Text(branchSourcePegURL)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Picker("类型", selection: $branchKind) {
                Text("分支").tag(BranchReferenceKind.branch)
                Text("标签").tag(BranchReferenceKind.tag)
            }
            TextField("名称", text: $branchName)
            TextField("提交说明", text: $branchMessage)
            HStack {
                Spacer()
                Button("取消") { showBranchSheet = false }
                Button("创建") {
                    Task { await confirmCreateBranch() }
                }
                .disabled(branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private var checkoutExportSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(checkoutExportIsExport ? "导出 r\(checkoutExportRevision.value)" : "检出 r\(checkoutExportRevision.value)")
                .font(.headline)
            Text(checkoutExportPegURL)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Picker("操作", selection: $checkoutExportIsExport) {
                Text("检出 (Checkout)").tag(false)
                Text("导出 (Export)").tag(true)
            }
            Text("将弹出目录选择器，选择目标文件夹。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { showCheckoutExportSheet = false }
                Button("选择目录…") {
                    Task { await confirmCheckoutOrExport() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private var confirmSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(pendingConfirmTitle)
                .font(.headline)
            Text(pendingConfirmDetail)
                .font(.body)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") {
                    pendingConfirmAction = nil
                    showConfirmSheet = false
                }
                Button("确认执行") {
                    let action = pendingConfirmAction
                    pendingConfirmAction = nil
                    showConfirmSheet = false
                    Task { await action?() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    @ViewBuilder
    private var revisionPropertySheet: some View {
        if let vm = revisionPropertyViewModel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("r\(vm.revision.value) 修订属性")
                        .font(.headline)
                    Spacer()
                    if vm.state == .loading || vm.state == .saving {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(vm.target)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if revisionPropertyEditMode {
                    TextField("作者", text: $revisionAuthor)
                        .textFieldStyle(.roundedBorder)
                    Text("日志说明").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $revisionMessage)
                        .font(.body)
                        .frame(minHeight: 110)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.25))
                        }
                }

                if case .error(let message) = vm.state {
                    Text("仓库拒绝修订属性操作：\(message)\n请检查仓库 pre-revprop-change hook。")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                List(vm.properties, id: \.name) { property in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(property.name).font(.caption.monospaced().weight(.semibold))
                        Text(property.value.isEmpty ? "（空）" : property.value)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 3)
                }
                .frame(minHeight: 220)

                HStack {
                    Button("刷新") { Task { await vm.load() } }
                    Spacer()
                    Button("关闭") { showRevisionPropertySheet = false }
                    if revisionPropertyEditMode {
                        Button("保存") { Task { await saveRevisionProperties(vm) } }
                            .disabled(
                                revisionAuthor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || vm.state == .saving
                            )
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("编辑") {
                            revisionAuthor = vm.author
                            revisionMessage = vm.message
                            revisionPropertyEditMode = true
                        }
                    }
                }
            }
            .padding(20)
            .frame(minWidth: 560, minHeight: 480)
        }
    }

    @ViewBuilder
    private var statisticsSheet: some View {
        let entries = filteredEntries(viewModel?.entries ?? [])
        let statistics = LogStatisticsBuilder.build(entries: entries)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("当前过滤结果：\(statistics.totalRevisions) 条修订")
                        .font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], spacing: 12) {
                        statisticValue("修订", value: "\(statistics.totalRevisions)")
                        statisticValue("作者", value: "\(statistics.totalAuthors)")
                        statisticValue("变更路径", value: "\(statistics.totalChangedPaths)")
                        statisticValue("活跃天数", value: "\(statistics.activeDays)")
                        statisticValue("日均提交", value: String(format: "%.2f", statistics.averageCommitsPerDay))
                        statisticValue("周均提交", value: String(format: "%.2f", statistics.averageCommitsPerWeek))
                    }

                    Text("作者排名").font(.headline)
                    ForEach(statistics.authors, id: \.author) { author in
                        HStack(spacing: 8) {
                            Text(author.author).lineLimit(1)
                            ProgressView(value: author.percentage)
                                .frame(maxWidth: .infinity)
                            Text("\(author.commits)（\(Int(author.percentage * 100))%）")
                                .font(.caption.monospaced())
                                .frame(width: 110, alignment: .trailing)
                        }
                    }

                    Text("按日活动").font(.headline)
                    ForEach(statistics.activity.suffix(31), id: \.date) { day in
                        HStack {
                            Text(day.date.formatted(date: .abbreviated, time: .omitted))
                                .frame(width: 110, alignment: .leading)
                            ProgressView(value: Double(day.commits), total: Double(max(1, statistics.activity.map(\.commits).max() ?? 1)))
                            Text("\(day.commits)").font(.caption.monospaced())
                        }
                    }

                    Text("动作汇总").font(.headline)
                    HStack {
                        ForEach(statistics.actions, id: \.action) { action in
                            Text("\(action.action.rawValue)：\(action.count)")
                                .font(.caption.monospaced())
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("日志统计")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showStatisticsSheet = false }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 560)
    }

    private func statisticValue(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospaced().weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func logDataSourceLabel(_ source: LogDataSource) -> String {
        switch source {
        case .live:
            return "在线"
        case .offlineCache(let updatedAt):
            return "离线缓存 · \(updatedAt.formatted(date: .abbreviated, time: .shortened))"
        case .fallbackCache(let updatedAt, _):
            return "网络不可用，已回退缓存 · \(updatedAt.formatted(date: .abbreviated, time: .shortened))"
        }
    }

    private func filteredEntries(_ entries: [LogEntry]) -> [LogEntry] {
        entries.filter {
            LogFilterPolicy.matches(
                $0,
                authorQuery: authorFilter,
                messageQuery: messageFilter,
                pathQuery: pathFilter
            )
        }
    }

    private func applyStopOnCopy(_ enabled: Bool) async {
        guard let viewModel else { return }
        viewModel.stopOnCopy = enabled
        await reloadPreservingFilters(viewModel: viewModel)
    }

    private func reload() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            viewModel = nil
            workingCopyURL = ""
            return
        }
        let settings = await session.settingsStore.settings()
        let graphLogIntent = navigator.consumePendingRevisionGraphLog()
        let wc = URL(fileURLWithPath: record.localPath)
        if offlineMode {
            workingCopyURL = record.repoURL
            repositoryRoot = record.repoURL
        } else {
            do {
                let info = try await session.svnService.info(wc: wc, target: "")
                workingCopyURL = info.url
                repositoryRoot = info.repositoryRoot ?? info.url
            } catch {
                workingCopyURL = record.repoURL
                repositoryRoot = workingCopyURL
            }
        }
        let logTarget = graphLogIntent?.url ?? record.repoURL
        let vm = LogViewModel(
            workingCopy: wc,
            target: graphLogIntent?.url ?? "",
            batchSize: settings.logBatchSize,
            logProvider: session.svnService,
            logCache: session.logCacheStore,
            cacheIdentity: LogCacheIdentity(
                repositoryRoot: record.repoURL,
                target: logTarget
            ),
            cachePolicy: settings.logCachePolicy
        )
        vm.stopOnCopy = stopOnCopy
        vm.offlineMode = offlineMode
        viewModel = vm
        let from = graphLogIntent?.revision ?? Revision(record.revision?.value ?? 1)
        await vm.loadInitial(from: from)
        if let selectedRevision,
           vm.entries.contains(where: { $0.revision.value == selectedRevision }) {
            // 保留仍存在的选中修订
        } else {
            self.selectedRevision = vm.entries.first?.revision.value
        }
        await consumePendingRevisionPropertiesIntent()
    }

    private func reloadPreservingFilters(viewModel: LogViewModel) async {
        guard let record = workspaceController.selectedRecord, record.isValid else { return }
        let from = Revision(record.revision?.value ?? 1)
        await viewModel.loadInitial(from: from)
        if let selectedRevision,
           !viewModel.entries.contains(where: { $0.revision.value == selectedRevision }) {
            self.selectedRevision = viewModel.entries.first?.revision.value
        }
    }

    private func updateTo(_ revision: Revision) async {
        guard let record = workspaceController.selectedRecord else { return }
        let wc = URL(fileURLWithPath: record.localPath)
        let actions = WorkingCopyActionsViewModel(
            workingCopy: wc,
            actionProvider: session.svnService,
            statusProvider: session.svnService
        )
        await actions.update(revision: revision)
        if case .updateCompleted = actions.state {
            statusText = "已更新到 r\(revision.value)"
            navigator.selectMode(.changes)
        } else if case .error(let message) = actions.state {
            errorText = message
        }
    }

    /// 执行 T2.3 日志右键动作（L01/L02/L04–L08）。
    private func performLogAction(
        _ command: SvnCommandID,
        changedPath: String,
        revision: Revision
    ) async {
        errorText = nil
        if command == .logEditAuthorOrMessage || command == .logShowRevisionProperties {
            await openRevisionProperties(
                revision: revision,
                edit: command == .logEditAuthorOrMessage
            )
            return
        }
        guard !workingCopyURL.isEmpty else {
            errorText = "无法解析工作副本 URL，请刷新后重试"
            return
        }
        guard let intent = LogContextActionPolicy.intent(
            command: command,
            changedPath: changedPath,
            revision: revision,
            workingCopyURL: workingCopyURL
        ) else {
            errorText = "无法解析路径「\(changedPath)」相对工作副本 URL，请确认已刷新且路径属于当前 WC"
            return
        }

        switch intent {
        case .compareWithWorkingCopy(let path, let rev):
            navigator.pendingLogDiff = PendingLogDiffIntent(path: path, revision: rev, kind: .workingCopy)
            navigator.selectMode(.changes)
            statusText = "与工作副本比较：\(path) @ r\(rev.value)"
            navigator.lastAutomationMessage = statusText

        case .compareWithPrevious(let path, let rev):
            navigator.pendingLogDiff = PendingLogDiffIntent(path: path, revision: rev, kind: .previous)
            navigator.selectMode(.changes)
            statusText = "与上一修订比较：\(path) @ r\(rev.value)"
            navigator.lastAutomationMessage = statusText

        case .compareAndBlame(let path, let fromRevision, let toRevision):
            navigator.pendingBlameIntent = PendingBlameIntent(
                path: path,
                fromRevision: fromRevision,
                toRevision: toRevision,
                mode: .differences
            )
            navigator.selectMode(.blame)
            statusText = "Blame 差异：\(path) r\(fromRevision.value)–r\(toRevision.value)"
            navigator.lastAutomationMessage = statusText

        case .showUnifiedDiff(let path, let rev):
            await showUnifiedDiff(path: path, revision: rev)

        case .saveRevision(let path, let rev):
            await saveRevision(path: path, revision: rev)

        case .openRevision(let path, let rev):
            await openRevision(path: path, revision: rev)

        case .blame(let path, let rev):
            navigator.pendingBlameIntent = PendingBlameIntent(path: path, revision: rev)
            navigator.selectMode(.blame)
            statusText = "Blame \(path)（日志 r\(rev.value)）"
            navigator.lastAutomationMessage = statusText

        case .browseRepository(_, let rev, let url):
            navigator.pendingBrowseURL = url
            navigator.pendingBrowseRevision = rev
            navigator.selectMode(.browser)
            statusText = "浏览 \(url) @ r\(rev.value)"
            navigator.lastAutomationMessage = statusText

        case .createBranchTag(let peg, let rev):
            branchSourcePegURL = peg
            branchRevision = rev
            branchName = ""
            branchMessage = "create from r\(rev.value)"
            showBranchSheet = true

        case .updateToRevision(let path, let rev):
            pendingConfirmTitle = "更新到 r\(rev.value)？"
            pendingConfirmDetail = "将对「\(path)」执行 svn update -r \(rev.value)。工作副本将变为该修订（可能 mixed-rev）。"
            pendingConfirmAction = { await self.updateItemToRevision(path: path, revision: rev) }
            showConfirmSheet = true

        case .revertToRevision(let path, let rev):
            pendingConfirmTitle = "还原到 r\(rev.value)？"
            pendingConfirmDetail = "将对「\(path)」执行反向合并（HEAD→r\(rev.value)），撤销之后的本地未提交合并结果需自行处理。此操作会修改工作副本。"
            pendingConfirmAction = { await self.revertToRevision(path: path, revision: rev) }
            showConfirmSheet = true

        case .revertChangesFromRevision(let path, let rev):
            pendingConfirmTitle = "撤销 r\(rev.value) 的更改？"
            pendingConfirmDetail = "将对「\(path)」反向合并单次修订 r\(rev.value)（等价 -c -\(rev.value)）。此操作会修改工作副本。"
            pendingConfirmAction = { await self.revertChangesFromRevision(path: path, revision: rev) }
            showConfirmSheet = true

        case .checkoutOrExport(let peg, let rev):
            checkoutExportPegURL = peg
            checkoutExportRevision = rev
            checkoutExportIsExport = false
            showCheckoutExportSheet = true

        case .mergeRevisionTo(let sourceURL, let rev):
            pendingConfirmTitle = "将 r\(rev.value) 合并到当前工作副本？"
            pendingConfirmDetail = "来源：\(sourceURL)\n将执行单修订合并（svn merge -c \(rev.value)），并可能产生冲突。"
            pendingConfirmAction = { await self.mergeRevisionTo(sourceURL: sourceURL, revision: rev) }
            showConfirmSheet = true
        }
    }

    private func consumePendingRevisionPropertiesIntent() async {
        guard let intent = navigator.consumePendingRevisionPropertiesIntent() else { return }
        selectedRevision = intent.revision.value
        await openRevisionProperties(
            revision: intent.revision,
            edit: intent.command == .logEditAuthorOrMessage,
            target: intent.target
        )
    }

    private func openRevisionProperties(
        revision: Revision,
        edit: Bool,
        target explicitTarget: String? = nil
    ) async {
        guard let record = workspaceController.selectedRecord else {
            errorText = "未选择工作副本"
            return
        }
        let target = explicitTarget?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTarget = target?.isEmpty == false
            ? target!
            : (repositoryRoot.isEmpty ? workingCopyURL : repositoryRoot)
        guard !resolvedTarget.isEmpty else {
            errorText = "无法解析仓库 URL"
            return
        }

        let vm = RevisionPropertyViewModel(
            workingCopy: URL(fileURLWithPath: record.localPath),
            target: resolvedTarget,
            revision: revision,
            provider: session.svnService
        )
        revisionPropertyViewModel = vm
        revisionPropertyEditMode = edit
        showRevisionPropertySheet = true
        await vm.load()
        revisionAuthor = vm.author
        revisionMessage = vm.message
    }

    private func saveRevisionProperties(_ vm: RevisionPropertyViewModel) async {
        await vm.save(author: revisionAuthor, message: revisionMessage)
        guard vm.state == .loaded else { return }
        revisionAuthor = vm.author
        revisionMessage = vm.message
        statusText = "已更新 r\(vm.revision.value) 的作者与日志说明"
        navigator.lastAutomationMessage = statusText
        if let viewModel {
            await reloadPreservingFilters(viewModel: viewModel)
        }
    }

    private func mergeRevisionTo(sourceURL: String, revision: Revision) async {
        guard let record = workspaceController.selectedRecord else { return }
        let wc = URL(fileURLWithPath: record.localPath)
        do {
            let summary = try await session.svnService.mergeRevisionTo(
                wc: wc,
                source: sourceURL,
                revision: revision,
                dryRun: false,
                auth: nil
            )
            if summary.conflicted > 0 {
                navigator.openMergeConflicts(
                    paths: summary.affectedPaths.filter { $0.action == .conflicted }.map(\.path)
                )
                statusText = "r\(revision.value) 已合并，但产生了冲突"
            } else {
                statusText = "已将 r\(revision.value) 合并到当前工作副本"
                navigator.selectMode(.changes)
            }
        } catch {
            errorText = "合并 r\(revision.value) 失败：\(error)"
        }
    }

    private func confirmCreateBranch() async {
        guard workspaceController.selectedRecord != nil else { return }
        let settings = await session.settingsStore.settings()
        let root = repositoryRoot.isEmpty ? workingCopyURL : repositoryRoot
        let copyVM = BranchCopyViewModel(copyProvider: session.svnService)
        await copyVM.create(
            kind: branchKind,
            source: branchSourcePegURL,
            repositoryRoot: root,
            name: branchName,
            layout: settings.branchLayout,
            message: branchMessage
        )
        showBranchSheet = false
        switch copyVM.state {
        case .completed(let rev):
            statusText = "已创建 \(branchKind == .tag ? "标签" : "分支") \(branchName) @ r\(rev.value)"
            navigator.selectMode(.branches)
        case .error(let message):
            errorText = message
        default:
            break
        }
    }

    private func updateItemToRevision(path: String, revision: Revision) async {
        guard let record = workspaceController.selectedRecord else { return }
        let wc = URL(fileURLWithPath: record.localPath)
        let actions = WorkingCopyActionsViewModel(
            workingCopy: wc,
            actionProvider: session.svnService,
            statusProvider: session.svnService
        )
        let paths = path == "." ? [] : [path]
        await actions.update(paths: paths, revision: revision)
        if case .updateCompleted = actions.state {
            statusText = "已更新 \(path) 到 r\(revision.value)"
            navigator.selectMode(.changes)
        } else if case .error(let message) = actions.state {
            errorText = message
        }
    }

    private func revertToRevision(path: String, revision: Revision) async {
        guard let record = workspaceController.selectedRecord else { return }
        let wc = URL(fileURLWithPath: record.localPath)
        do {
            let head = try await session.svnService.repositoryHeadRevision(wc: wc, target: path == "." ? "" : path)
            guard let range = LogContextActionPolicy.revertToRevisionRange(head: head, target: revision) else {
                errorText = "仓库 HEAD (r\(head.value)) 未晚于目标 r\(revision.value)，无需还原"
                return
            }
            let summary = try await session.svnService.merge(
                wc: wc,
                source: path,
                range: range,
                dryRun: false
            )
            statusText = "已还原到 r\(revision.value)：冲突 \(summary.conflicted)"
            navigator.selectMode(.changes)
        } catch {
            errorText = String(describing: error)
        }
    }

    private func revertChangesFromRevision(path: String, revision: Revision) async {
        guard let record = workspaceController.selectedRecord else { return }
        let wc = URL(fileURLWithPath: record.localPath)
        guard let range = LogContextActionPolicy.reverseSingleRevisionRange(revision) else {
            errorText = "无法对 r0 执行反向合并"
            return
        }
        do {
            let summary = try await session.svnService.merge(
                wc: wc,
                source: path,
                range: range,
                dryRun: false
            )
            statusText = "已撤销 r\(revision.value)：冲突 \(summary.conflicted)"
            navigator.selectMode(.changes)
        } catch {
            errorText = String(describing: error)
        }
    }

    private func confirmCheckoutOrExport() async {
        let destination: URL? = await MainActor.run {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = checkoutExportIsExport ? "导出到此目录" : "检出到此目录"
            guard panel.runModal() == .OK else { return nil }
            return panel.url
        }
        guard let destination else { return }
        showCheckoutExportSheet = false

        // peg URL：仅剥离末尾 @数字，保留 user@host
        let peg = checkoutExportPegURL
        let url = LogContextActionPolicy.stripPegRevision(from: peg)
        let rev = checkoutExportRevision
        let leaf = URL(string: url)?.lastPathComponent
        let folderName = (leaf?.isEmpty == false ? leaf! : "svn-r\(rev.value)")
        let target = destination.appendingPathComponent(folderName)

        do {
            if checkoutExportIsExport {
                try await session.svnService.export(url: url, to: target, revision: rev, ignoreExternals: false, auth: nil)
                statusText = "已导出 r\(rev.value) → \(target.path)"
            } else {
                try await session.svnService.checkout(
                    url: url,
                    to: target,
                    depth: .infinity,
                    revision: rev,
                    ignoreExternals: false,
                    auth: nil
                )
                statusText = "已检出 r\(rev.value) → \(target.path)"
            }
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } catch {
            errorText = String(describing: error)
        }
    }

    private func showUnifiedDiff(path: String, revision: Revision) async {
        guard let record = workspaceController.selectedRecord else { return }
        let wc = URL(fileURLWithPath: record.localPath)
        let previous = Revision(max(0, revision.value - 1))
        do {
            let text = try await session.svnService.diff(
                wc: wc,
                target: path,
                r1: previous,
                r2: revision
            )
            unifiedDiffText = text.isEmpty ? "（无差异）" : text
            showUnifiedDiffSheet = true
            statusText = "统一 Diff：\(path) r\(previous.value):r\(revision.value)"
        } catch {
            errorText = String(describing: error)
        }
    }

    private func materializeRevisionData(path: String, revision: Revision) async throws -> (Data, String) {
        guard let record = workspaceController.selectedRecord else {
            throw SvnError.other(code: nil, stderr: "noWorkingCopy")
        }
        let wc = URL(fileURLWithPath: record.localPath)
        let info = try await session.svnService.info(wc: wc, target: path)
        let data = try await session.svnService.cat(
            url: info.url,
            revision: revision,
            sizeLimit: 20 * 1024 * 1024,
            auth: nil
        )
        return (data, URL(fileURLWithPath: path).lastPathComponent)
    }

    private func saveRevision(path: String, revision: Revision) async {
        do {
            let (data, basename) = try await materializeRevisionData(path: path, revision: revision)
            let saved: URL? = await MainActor.run {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = basename
                panel.canCreateDirectories = true
                guard panel.runModal() == .OK else { return nil }
                return panel.url
            }
            guard let url = saved else { return }
            try data.write(to: url, options: .atomic)
            statusText = "已另存 r\(revision.value) → \(url.path)"
        } catch {
            errorText = String(describing: error)
        }
    }

    private func openRevision(path: String, revision: Revision) async {
        do {
            let (data, basename) = try await materializeRevisionData(path: path, revision: revision)
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("MacSvnLogOpen", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("r\(revision.value)-\(basename)")
            try data.write(to: file, options: .atomic)
            NSWorkspace.shared.open(file)
            statusText = "已打开 r\(revision.value) · \(basename)"
        } catch {
            errorText = String(describing: error)
        }
    }
}
