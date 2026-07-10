import SwiftUI
import AppKit
import MacSvnCore

/// 历史页：左侧修订列表，右侧详情（说明 / 变更路径 / 操作）。
///
/// T2.2：过滤 / stop-on-copy / Next·All / Actions。
/// T2.3：变更路径右键 L01–L08（L03 属 T3，菜单不提供）。
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
    @State private var statusText: String?
    @State private var selectedRevision: Int?
    /// 当前 WC 的 `svn info` URL，供路径归一化与 Browse。
    @State private var workingCopyURL: String = ""
    @State private var repositoryRoot: String = ""
    @State private var unifiedDiffText: String?
    @State private var showUnifiedDiffSheet = false

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
            HStack {
                Text("历史")
                    .font(.title2.weight(.semibold))
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
                Button("Next") {
                    Task { await viewModel?.loadMore() }
                }
                .disabled(viewModel?.hasMore != true || viewModel?.isLoading == true)
                .help("再加载一批（Tortoise Next）")
                Button("Show All") {
                    Task { await viewModel?.loadAll() }
                }
                .disabled(viewModel?.hasMore != true || viewModel?.isLoading == true)
                .help("循环拉取直至无更多（Tortoise Show All）")
            }
            .padding(16)

            HStack(spacing: 8) {
                TextField("作者过滤", text: $authorFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
                TextField("说明关键字", text: $messageFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                TextField("路径过滤", text: $pathFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                Toggle("Stop on copy", isOn: $stopOnCopy)
                    .toggleStyle(.checkbox)
                    .help("svn log --stop-on-copy：在分支拷贝点停止")
                    .onChange(of: stopOnCopy) { _, newValue in
                        Task { await applyStopOnCopy(newValue) }
                    }
                if let viewModel, viewModel.state == .loaded || viewModel.state == .loadingMore {
                    let shown = filteredEntries(viewModel.entries).count
                    Text("显示 \(shown) / 已载 \(viewModel.entries.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !pathFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, shown == 0, !viewModel.entries.isEmpty {
                        Text("路径过滤无命中（需 verbose 路径明细）")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

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
    }

    @ViewBuilder
    private func logRevisionContextMenu(path: String, revision: Revision) -> some View {
        ForEach(LogContextActionPolicy.t2RevisionActionIDs, id: \.rawValue) { command in
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
        let wc = URL(fileURLWithPath: record.localPath)
        do {
            let info = try await session.svnService.info(wc: wc, target: "")
            workingCopyURL = info.url
            repositoryRoot = info.repositoryRoot ?? info.url
        } catch {
            workingCopyURL = record.repoURL ?? ""
            repositoryRoot = workingCopyURL
        }
        let vm = LogViewModel(
            workingCopy: wc,
            target: "",
            batchSize: settings.logBatchSize,
            logProvider: session.svnService
        )
        vm.stopOnCopy = stopOnCopy
        viewModel = vm
        let from = Revision(record.revision?.value ?? 1)
        await vm.loadInitial(from: from)
        if let selectedRevision,
           vm.entries.contains(where: { $0.revision.value == selectedRevision }) {
            // 保留仍存在的选中修订
        } else {
            self.selectedRevision = vm.entries.first?.revision.value
        }
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

        case .showUnifiedDiff(let path, let rev):
            await showUnifiedDiff(path: path, revision: rev)

        case .saveRevision(let path, let rev):
            await saveRevision(path: path, revision: rev)

        case .openRevision(let path, let rev):
            await openRevision(path: path, revision: rev)

        case .blame(let path, let rev):
            navigator.pendingBlamePath = path
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
                try await session.svnService.export(url: url, to: target, revision: rev, auth: nil)
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
