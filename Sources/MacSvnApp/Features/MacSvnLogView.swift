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
    @State private var unifiedDiffText: String?
    @State private var showUnifiedDiffSheet = false

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
                                } else {
                                    Text("无变更路径，无法执行文件级动作")
                                }
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
                VStack(alignment: .leading, spacing: 16) {
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
                    LabeledContent("作者", value: entry.author.isEmpty ? "unknown" : entry.author)

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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("变更路径（\(entry.changedPaths.count)）")
                            .font(.headline)
                        if entry.changedPaths.isEmpty {
                            Text("此批次未带路径明细（可刷新或加载 verbose 日志）")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(entry.changedPaths.enumerated()), id: \.offset) { _, change in
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
                                }
                            }
                        }
                    }

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
                    }
                }
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
    private func logPathContextMenu(path: String, revision: Revision) -> some View {
        ForEach(LogContextActionPolicy.t2ActionIDs, id: \.rawValue) { command in
            Button(SvnCommandCatalog.descriptor(for: command)?.displayName ?? command.rawValue) {
                Task { await performLogAction(command, changedPath: path, revision: revision) }
            }
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
        let wc = URL(fileURLWithPath: record.localPath)
        do {
            let info = try await session.svnService.info(wc: wc, target: "")
            workingCopyURL = info.url
        } catch {
            workingCopyURL = record.repoURL ?? ""
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
            errorText = "不支持的日志动作"
            return
        }

        switch intent {
        case .compareWithWorkingCopy(let path, let rev):
            navigator.pendingDiffCompareKind = .workingCopy
            navigator.pendingDiffRevision = rev
            navigator.pendingDiffPath = path
            navigator.selectMode(.changes)
            statusText = "与工作副本比较：\(path) @ r\(rev.value)"
            navigator.lastAutomationMessage = statusText

        case .compareWithPrevious(let path, let rev):
            navigator.pendingDiffCompareKind = .previous
            navigator.pendingDiffRevision = rev
            navigator.pendingDiffPath = path
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
            let panel = NSSavePanel()
            panel.nameFieldStringValue = basename
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
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
