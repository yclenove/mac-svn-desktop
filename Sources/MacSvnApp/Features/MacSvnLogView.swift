import SwiftUI
import MacSvnCore

/// 日志页：过滤 + 从条目发起 Diff / Update -r / 还原。
public struct MacSvnLogView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession

    @State private var viewModel: LogViewModel?
    @State private var errorText: String?
    @State private var authorFilter = ""
    @State private var messageFilter = ""
    @State private var statusText: String?

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
                Text("日志")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Button("刷新") { Task { await reload() } }
                Button("加载更多") {
                    Task { await viewModel?.loadMore() }
                }
                .disabled(viewModel?.hasMore != true || viewModel?.isLoading == true)
            }
            .padding(24)

            HStack {
                TextField("作者过滤", text: $authorFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
                TextField("说明关键字", text: $messageFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            if let statusText {
                Text(statusText).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24)
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red).padding(.horizontal, 24)
            }

            content
        }
        .onChange(of: workspaceController.selectedID) { _, _ in
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
                List(filteredEntries(viewModel.entries), id: \.revision.value) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("r\(entry.revision.value)").font(.headline.monospaced())
                            Text(entry.author.isEmpty ? "unknown" : entry.author).foregroundStyle(.secondary)
                            Spacer()
                            Text(entry.date?.formatted() ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(entry.message).font(.body)
                        if !entry.changedPaths.isEmpty {
                            Text(entry.changedPaths.prefix(8).map(\.path).joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                        HStack {
                            Button("查看 Diff") {
                                navigator.pendingDiffRevision = entry.revision
                                navigator.selectedRoute = .diff
                                navigator.lastAutomationMessage = "从日志打开 Diff：r\(entry.revision.value)"
                            }
                            Button("更新到此版本") {
                                Task { await updateTo(entry.revision) }
                            }
                            Button("还原首个变更文件") {
                                Task { await revertFirstPath(of: entry) }
                            }
                            .disabled(entry.changedPaths.isEmpty)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
                if viewModel.state == .loadingMore {
                    ProgressView().padding()
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
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
            navigator.selectedRoute = .changes
        } else if case .error(let message) = actions.state {
            errorText = message
        }
    }

    private func revertFirstPath(of entry: LogEntry) async {
        guard let record = workspaceController.selectedRecord,
              let path = entry.changedPaths.first?.path
        else { return }
        let wc = URL(fileURLWithPath: record.localPath)
        do {
            // 用 cat + 写回过于危险；此处走 svn merge -c -REV 的简化：update 文件到前一版本不可用时提示
            _ = try await session.svnService.diff(
                wc: wc,
                target: path,
                r1: Revision(max(0, entry.revision.value - 1)),
                r2: entry.revision
            )
            navigator.pendingDiffPath = path
            navigator.pendingDiffRevision = entry.revision
            navigator.selectedRoute = .diff
            statusText = "已打开 r\(entry.revision.value) 对 \(path) 的 Diff；还原请在变更页使用 Revert 或手工合并"
        } catch {
            errorText = error.localizedDescription
        }
    }
}
