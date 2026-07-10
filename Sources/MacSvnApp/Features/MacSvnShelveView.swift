import SwiftUI
import MacSvnCore

public struct MacSvnShelveView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let session: MacSvnAppSession

    @State private var paths: [String] = []
    @State private var selected: Set<String> = []
    @State private var viewModel: ShelveViewModel?
    @State private var name = ""
    @State private var statusText: String?

    public init(workspaceController: MacSvnWorkspaceController, session: MacSvnAppSession) {
        self.workspaceController = workspaceController
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("本地搁置")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                TextField("搁置名称", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                Button("Shelve") {
                    Task {
                        await viewModel?.shelve(name: name, paths: Array(selected))
                        statusText = "已搁置"
                        await reloadPaths()
                    }
                }
                .disabled(selected.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("安全快照") {
                    Task {
                        await viewModel?.createSafetySnapshot(name: name.isEmpty ? "safety" : name, paths: Array(selected))
                        statusText = "已创建安全快照"
                    }
                }
                .disabled(selected.isEmpty)
                Button("刷新") { Task { await viewModel?.load() } }
            }
            .padding(24)

            if let statusText {
                Text(statusText).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24)
            }

            if workspaceController.selectedRecord == nil {
                ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
            } else {
                HSplitView {
                    VStack(alignment: .leading) {
                        Text("变更路径").font(.headline).padding(.horizontal, 8)
                        MacSvnPathPicker(paths: paths, selection: $selected)
                    }
                    .frame(minWidth: 220)

                    VStack(alignment: .leading) {
                        List(viewModel?.snapshots ?? []) { snapshot in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(snapshot.name).font(.headline)
                                Text("\(snapshot.kind.rawValue) · \(snapshot.paths.count) 文件")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Button("预览") {
                                        Task { await viewModel?.preview(snapshot) }
                                    }
                                    Button("恢复") {
                                        Task {
                                            await viewModel?.restore(snapshot)
                                            statusText = "已恢复 \(snapshot.name)"
                                            await reloadPaths()
                                        }
                                    }
                                    Button("删除", role: .destructive) {
                                        Task { await viewModel?.delete(snapshot) }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        if !(viewModel?.previewText.isEmpty ?? true) {
                            ScrollView {
                                Text(viewModel?.previewText ?? "")
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 180)
                            .padding(8)
                            .border(Color.secondary.opacity(0.2))
                        }
                    }
                    .frame(minWidth: 360)
                }
            }
        }
        .task { await bootstrap() }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await bootstrap() }
        }
    }

    private func bootstrap() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            paths = []; viewModel = nil; return
        }
        let wc = URL(fileURLWithPath: record.localPath)
        viewModel = ShelveViewModel(workingCopy: wc, shelveProvider: session.shelveService)
        await viewModel?.load()
        await reloadPaths()
    }

    private func reloadPaths() async {
        guard let record = workspaceController.selectedRecord else { return }
        paths = await MacSvnPathLoader.loadPaths(
            svnService: session.svnService,
            wc: URL(fileURLWithPath: record.localPath)
        )
    }
}
