import SwiftUI
import MacSvnCore

/// Diff 页：接 DiffViewModel，展示 unified diff。
public struct MacSvnDiffView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let svnService: SvnService

    @State private var paths: [String] = []
    @State private var selectedPath: String?
    @State private var viewModel: DiffViewModel?
    @State private var errorText: String?

    public init(workspaceController: MacSvnWorkspaceController, svnService: SvnService) {
        self.workspaceController = workspaceController
        self.svnService = svnService
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Diff")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Button("刷新文件列表") {
                    Task { await reloadPaths() }
                }
            }
            .padding(24)

            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
            }

            if workspaceController.selectedRecord == nil {
                ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
            } else {
                HSplitView {
                    List(paths, id: \.self, selection: $selectedPath) { path in
                        Text(path)
                    }
                    .frame(minWidth: 220)
                    .onChange(of: selectedPath) { _, newValue in
                        guard let newValue else { return }
                        Task { await loadDiff(path: newValue) }
                    }

                    diffContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await reloadPaths() }
        }
        .task { await reloadPaths() }
    }

    @ViewBuilder
    private var diffContent: some View {
        if let viewModel {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("加载 diff…")
            case .binaryUnsupported:
                ContentUnavailableView("二进制文件", systemImage: "doc.zipper", description: Text("无法显示文本差异"))
            case .error(let message):
                ContentUnavailableView("失败", systemImage: "exclamationmark.triangle", description: Text(message))
            case .loaded:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.lines) { line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(color(for: line.kind))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(background(for: line.kind))
                        }
                    }
                    .padding(12)
                }
            }
        } else {
            ContentUnavailableView("选择文件", systemImage: "doc.text.magnifyingglass", description: Text("从左侧选择变更文件查看 diff"))
        }
    }

    private func reloadPaths() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            paths = []
            selectedPath = nil
            viewModel = nil
            return
        }
        let wc = URL(fileURLWithPath: record.localPath)
        do {
            let statuses = try await svnService.status(wc: wc)
            paths = statuses.map(\.path).sorted()
            viewModel = DiffViewModel(workingCopy: wc, diffProvider: svnService)
            errorText = nil
            if let selectedPath, paths.contains(selectedPath) {
                await loadDiff(path: selectedPath)
            } else {
                selectedPath = paths.first
                if let selectedPath {
                    await loadDiff(path: selectedPath)
                }
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadDiff(path: String) async {
        guard let viewModel else { return }
        await viewModel.load(target: path)
    }

    private func color(for kind: UnifiedDiffLineKind) -> Color {
        switch kind {
        case .addition: return .green
        case .deletion: return .red
        case .hunk, .metadata: return .secondary
        default: return .primary
        }
    }

    private func background(for kind: UnifiedDiffLineKind) -> Color {
        switch kind {
        case .addition: return Color.green.opacity(0.12)
        case .deletion: return Color.red.opacity(0.12)
        default: return .clear
        }
    }
}
