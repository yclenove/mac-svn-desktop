import SwiftUI
import MacSvnCore

/// 变更页：绑定 ChangesViewModel，展示状态列表并支持刷新/筛选。
public struct MacSvnChangesView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let statusProvider: any StatusProviding

    @State private var viewModel: ChangesViewModel?
    @State private var filterMode: FilterMode = .all
    @State private var searchText = ""

    private enum FilterMode: String, CaseIterable, Identifiable {
        case all = "全部"
        case modified = "已修改"
        case conflicts = "冲突"
        var id: String { rawValue }
    }

    public init(
        workspaceController: MacSvnWorkspaceController,
        statusProvider: any StatusProviding
    ) {
        self.workspaceController = workspaceController
        self.statusProvider = statusProvider
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await bindAndRefresh() }
        }
        .task { await bindAndRefresh() }
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
            TextField("搜索文件名", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            Button("刷新") {
                Task { await viewModel?.refresh() }
            }
            .disabled(viewModel == nil)
        }
        .padding(24)
        .onChange(of: filterMode) { _, _ in applyFilters() }
        .onChange(of: searchText) { _, _ in applyFilters() }
    }

    @ViewBuilder
    private var content: some View {
        if workspaceController.selectedRecord == nil {
            ContentUnavailableView("未选择工作副本", systemImage: "externaldrive", description: Text("请先在「工作副本」中添加并选中目录"))
        } else if let viewModel {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("正在读取 status…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                ContentUnavailableView("读取失败", systemImage: "exclamationmark.triangle", description: Text(message))
            case .loaded:
                List(viewModel.visibleFlatEntries, id: \.path) { entry in
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
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func bindAndRefresh() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            viewModel = nil
            return
        }
        let vm = ChangesViewModel(
            workingCopy: URL(fileURLWithPath: record.localPath),
            statusProvider: statusProvider
        )
        viewModel = vm
        applyFilters()
        await vm.refresh()
    }

    private func applyFilters() {
        guard let viewModel else { return }
        viewModel.searchText = searchText
        switch filterMode {
        case .all:
            viewModel.filter = .all
        case .modified:
            viewModel.filter = .items([.modified, .added, .deleted, .replaced, .missing])
        case .conflicts:
            viewModel.filter = .conflicts
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
        default: return status.rawValue.prefix(1).uppercased()
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
