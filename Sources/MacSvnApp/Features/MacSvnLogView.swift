import SwiftUI
import MacSvnCore

/// 历史页：左侧修订列表，右侧详情（说明 / 变更路径 / 操作）。
public struct MacSvnLogView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession

    @State private var viewModel: LogViewModel?
    @State private var errorText: String?
    @State private var authorFilter = ""
    @State private var messageFilter = ""
    @State private var statusText: String?
    @State private var selectedRevision: Int?

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
                Button("加载更多") {
                    Task { await viewModel?.loadMore() }
                }
                .disabled(viewModel?.hasMore != true || viewModel?.isLoading == true)
            }
            .padding(16)

            HStack {
                TextField("作者过滤", text: $authorFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
                TextField("说明关键字", text: $messageFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
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
                            .tag(entry.revision.value)
                            .padding(.vertical, 2)
                        }
                    }
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

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
                                        navigator.pendingDiffPath = change.path
                                        navigator.pendingDiffRevision = entry.revision
                                        navigator.selectMode(.changes)
                                        navigator.lastAutomationMessage = "查看 r\(entry.revision.value) · \(change.path)"
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    HStack {
                        Button("在变更区查看 Diff") {
                            navigator.pendingDiffRevision = entry.revision
                            if let first = entry.changedPaths.first?.path {
                                navigator.pendingDiffPath = first
                            }
                            navigator.selectMode(.changes)
                        }
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

    private func filteredEntries(_ entries: [LogEntry]) -> [LogEntry] {
        let author = authorFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let message = messageFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            let authorOK = author.isEmpty || entry.author.lowercased().contains(author)
            let messageOK = message.isEmpty || entry.message.lowercased().contains(message)
            return authorOK && messageOK
        }
    }

    private func reload() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            viewModel = nil
            return
        }
        let settings = await session.settingsStore.settings()
        let wc = URL(fileURLWithPath: record.localPath)
        let vm = LogViewModel(
            workingCopy: wc,
            target: "",
            batchSize: settings.logBatchSize,
            logProvider: session.svnService
        )
        viewModel = vm
        let from = Revision(record.revision?.value ?? 1)
        await vm.loadInitial(from: from)
        if selectedRevision == nil {
            selectedRevision = vm.entries.first?.revision.value
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
}
