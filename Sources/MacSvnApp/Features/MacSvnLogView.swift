import SwiftUI
import MacSvnCore

/// 日志页：接 LogViewModel，支持分页加载更多。
public struct MacSvnLogView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let session: MacSvnAppSession

    @State private var viewModel: LogViewModel?
    @State private var errorText: String?

    public init(workspaceController: MacSvnWorkspaceController, session: MacSvnAppSession) {
        self.workspaceController = workspaceController
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("日志")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Button("刷新") {
                    Task { await reload() }
                }
                Button("加载更多") {
                    Task { await viewModel?.loadMore() }
                }
                .disabled(viewModel?.hasMore != true || viewModel?.isLoading == true)
            }
            .padding(24)

            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
            }

            if workspaceController.selectedRecord == nil {
                ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
            } else if let viewModel {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("加载日志…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .error(let message):
                    ContentUnavailableView("失败", systemImage: "exclamationmark.triangle", description: Text(message))
                case .loaded, .loadingMore:
                    List(viewModel.entries, id: \.revision.value) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("r\(entry.revision.value)")
                                    .font(.headline.monospaced())
                                Text(entry.author.isEmpty ? "unknown" : entry.author)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(entry.date?.formatted() ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .font(.body)
                            if !entry.changedPaths.isEmpty {
                                Text(entry.changedPaths.prefix(8).map(\.path).joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if viewModel.state == .loadingMore {
                        ProgressView()
                            .padding()
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await reload() }
        }
        .task { await reload() }
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
            target: ".",
            batchSize: settings.logBatchSize,
            logProvider: session.svnService
        )
        viewModel = vm
        // HEAD 起加载：用一个足够大的 revision 作为起点（后端通常接受 HEAD 语义由 from 控制）
        let start = record.revision ?? Revision(999_999_999)
        await vm.loadInitial(from: start)
        errorText = nil
    }
}
