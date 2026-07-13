import SwiftUI
import MacSvnCore
import AppKit

public struct MacSvnShelveView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession

    @State private var paths: [String] = []
    @State private var selected: Set<String> = []
    @State private var viewModel: ShelveViewModel?
    @State private var patchViewModel: PatchViewModel?
    @State private var name = ""
    @State private var statusText: String?
    @State private var showPatchSheet = false
    @State private var patchOperation: PatchOperation = .create
    @State private var patchPath = ""

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
                Menu("Patch") {
                    Button("创建 Patch") { presentPatch(.create) }
                    Button("应用 Patch") { presentPatch(.apply) }
                }
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
        .onChange(of: navigator.pendingPatchIntent) { _, _ in
            consumePendingPatchIntent()
        }
        .sheet(isPresented: $showPatchSheet) {
            patchSheet
        }
    }

    private func bootstrap() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            paths = []; viewModel = nil; patchViewModel = nil; return
        }
        let wc = URL(fileURLWithPath: record.localPath)
        viewModel = ShelveViewModel(workingCopy: wc, shelveProvider: session.shelveService)
        patchViewModel = PatchViewModel(workingCopy: wc, provider: session.svnService)
        await viewModel?.load()
        await reloadPaths()
        consumePendingPatchIntent()
    }

    private func reloadPaths() async {
        guard let record = workspaceController.selectedRecord else { return }
        paths = await MacSvnPathLoader.loadPaths(
            svnService: session.svnService,
            wc: URL(fileURLWithPath: record.localPath)
        )
    }

    private var patchSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(patchOperation == .create ? "创建 Patch" : "应用 Patch")
                .font(.title2.weight(.semibold))
            HStack {
                TextField(
                    patchOperation == .create ? "输出文件路径" : "Patch 文件路径",
                    text: $patchPath
                )
                .textFieldStyle(.roundedBorder)
                Button("选择…") { choosePatchPath() }
            }
            if patchOperation == .create {
                Text("当前已选择 \(selected.count) 个变更路径")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("取消") { showPatchSheet = false }
                Button("执行") { Task { await executePatch() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        patchPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (patchOperation == .create && selected.isEmpty)
                    )
            }
        }
        .padding(24)
        .frame(minWidth: 460)
    }

    private func presentPatch(_ operation: PatchOperation) {
        patchOperation = operation
        patchPath = ""
        showPatchSheet = true
    }

    private func choosePatchPath() {
        if patchOperation == .create {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "changes.patch"
            panel.prompt = "创建 Patch"
            if panel.runModal() == .OK, let url = panel.url {
                patchPath = url.path
            }
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.prompt = "应用 Patch"
            if panel.runModal() == .OK, let url = panel.url {
                patchPath = url.path
            }
        }
    }

    private func consumePendingPatchIntent() {
        guard patchViewModel != nil, let intent = navigator.consumePendingPatchIntent() else { return }
        patchOperation = intent.command == .createPatch ? .create : .apply
        if !intent.paths.isEmpty {
            selected = Set(intent.paths)
        }
        patchPath = intent.patchFile ?? ""
        showPatchSheet = true
    }

    private func executePatch() async {
        guard let patchViewModel else { return }
        let file = URL(fileURLWithPath: patchPath.trimmingCharacters(in: .whitespacesAndNewlines))
        switch patchOperation {
        case .create:
            await patchViewModel.create(paths: Array(selected).sorted(), to: file)
        case .apply:
            await patchViewModel.apply(patchFile: file)
        }

        switch patchViewModel.state {
        case .completed(.create):
            statusText = "Patch 创建完成：\(file.path)"
            showPatchSheet = false
        case .completed(.apply):
            statusText = "Patch 应用完成"
            showPatchSheet = false
            await reloadPaths()
        case .error(let message):
            statusText = "Patch 操作失败：\(message)"
        default:
            break
        }
    }
}
