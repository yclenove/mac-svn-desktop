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
    @State private var statusText: LocalizedStringKey?
    @State private var showPatchSheet = false
    @State private var patchOperation: PatchOperation = .create
    @State private var patchPath = ""
    @State private var message = ""
    @State private var keepLocalChanges = false

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
                Text("搁置")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Menu("Patch") {
                    Button("创建 Patch") { presentPatch(.create) }
                    Button("应用 Patch") { presentPatch(.apply) }
                }
                Button("刷新") { Task { await refreshShelves() } }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            HStack(spacing: 12) {
                TextField("搁置名称", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 150, maxWidth: 220)
                TextField("说明（可选）", text: $message)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180, maxWidth: 300)
                Toggle("保留本地改动", isOn: $keepLocalChanges)
                    .toggleStyle(.checkbox)
                Button("官方 Shelve") { Task { await createOfficialShelf() } }
                    .disabled(!isOfficialAvailable || !canCreateShelf)
                Menu("本地快照") {
                    Button("Shelve 到本地") { Task { await createLocalShelf() } }
                        .disabled(!canCreateShelf)
                    Button("创建安全快照") { Task { await createSafetySnapshot() } }
                        .disabled(selected.isEmpty)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

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
                        HStack {
                            Text("官方 Shelves").font(.headline)
                            Spacer()
                            officialAvailabilityView
                        }
                        .padding(.horizontal, 8)

                        List(viewModel?.officialShelves ?? []) { shelf in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(shelf.name).font(.headline)
                                Text("V\(shelf.latestVersion) · \(shelf.pathCount) 个路径 · \(shelf.ageSummary)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let message = shelf.message, !message.isEmpty {
                                    Text(message).font(.caption).lineLimit(2)
                                }
                                HStack {
                                    Button("Diff") { Task { await previewOfficialShelf(shelf) } }
                                    Button("Log") { Task { await showOfficialLog(shelf) } }
                                    Button("Unshelve") { Task { await unshelve(shelf, drop: false) } }
                                    Button("Unshelve + Drop") { Task { await unshelve(shelf, drop: true) } }
                                    Button("Drop", role: .destructive) { Task { await dropOfficialShelf(shelf) } }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(minHeight: 150)

                        Divider()
                        Text("本地 Patch 快照").font(.headline).padding(.horizontal, 8)
                        List(viewModel?.snapshots ?? []) { snapshot in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(snapshot.name).font(.headline)
                                Text("\(snapshot.kind.rawValue) · \(snapshot.paths.count) 个路径")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Button("预览") { Task { await previewLocalSnapshot(snapshot) } }
                                    Button("恢复") { Task { await restoreLocalSnapshot(snapshot) } }
                                    if snapshot.kind == .manual {
                                        Button("迁移到官方") { Task { await migrate(snapshot) } }
                                            .disabled(!isOfficialAvailable)
                                    }
                                    Button("删除", role: .destructive) { Task { await deleteLocalSnapshot(snapshot) } }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(minHeight: 150)

                        shelfDetails
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

    private var canCreateShelf: Bool {
        !selected.isEmpty && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isOfficialAvailable: Bool {
        guard case .available = viewModel?.officialAvailability else { return false }
        return true
    }

    @ViewBuilder
    private var officialAvailabilityView: some View {
        switch viewModel?.officialAvailability {
        case .available(let version):
            Label {
                Text(LocalizedStringKey(version.displayName))
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
                .font(.caption)
                .foregroundStyle(.green)
        case .unavailable(let version, let reason):
            Label {
                Text("\(version.displayName) 不可用：\(reason)")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        case nil:
            ProgressView().controlSize(.small)
        }
    }

    @ViewBuilder
    private var shelfDetails: some View {
        let localPreview = viewModel?.previewText ?? ""
        let officialDiff = viewModel?.officialDiffText ?? ""
        let officialLog = viewModel?.officialLogText ?? ""
        if !localPreview.isEmpty || !officialDiff.isEmpty || !officialLog.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    detailBlock("官方 Diff", text: officialDiff)
                    detailBlock("官方 Log", text: officialLog)
                    detailBlock("本地 Patch", text: localPreview)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(maxHeight: 220)
            .border(Color.secondary.opacity(0.2))
        }
    }

    @ViewBuilder
    private func detailBlock(_ title: String, text: String) -> some View {
        if !text.isEmpty {
            Text(title).font(.caption.weight(.semibold))
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func refreshShelves() async {
        await viewModel?.load()
        if let error = viewModel?.officialError {
            statusText = "官方 shelf 列表加载失败：\(error)"
        }
    }

    private func createOfficialShelf() async {
        await viewModel?.officialShelve(
            name: name,
            paths: Array(selected).sorted(),
            message: message,
            keepLocal: keepLocalChanges
        )
        if updateStatus(for: .officialShelve, success: "官方 Shelve 创建完成") {
            await reloadPaths()
        }
    }

    private func createLocalShelf() async {
        await viewModel?.shelve(name: name, paths: Array(selected).sorted())
        if updateStatus(for: .shelve, success: "本地搁置创建完成") {
            await reloadPaths()
        }
    }

    private func createSafetySnapshot() async {
        let snapshotName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        await viewModel?.createSafetySnapshot(
            name: snapshotName.isEmpty ? "safety" : snapshotName,
            paths: Array(selected).sorted()
        )
        _ = updateStatus(for: .safetySnapshot, success: "安全快照创建完成")
    }

    private func previewOfficialShelf(_ shelf: SvnShelf) async {
        await viewModel?.officialDiff(shelf)
        _ = updateStatus(for: .officialDiff, success: "已加载 \(shelf.name) 的 Diff")
    }

    private func showOfficialLog(_ shelf: SvnShelf) async {
        await viewModel?.officialLog(shelf)
        _ = updateStatus(for: .officialLog, success: "已加载 \(shelf.name) 的版本记录")
    }

    private func unshelve(_ shelf: SvnShelf, drop: Bool) async {
        await viewModel?.officialUnshelve(shelf, drop: drop)
        let suffix = drop ? "并删除 shelf" : ""
        if updateStatus(for: .officialUnshelve, success: "已恢复 \(shelf.name) \(suffix)") {
            await reloadPaths()
        }
    }

    private func dropOfficialShelf(_ shelf: SvnShelf) async {
        await viewModel?.officialDrop(shelf)
        _ = updateStatus(for: .officialDrop, success: "已删除官方 shelf \(shelf.name)")
    }

    private func previewLocalSnapshot(_ snapshot: ShelveSnapshot) async {
        await viewModel?.preview(snapshot)
        _ = updateStatus(for: .preview, success: "已加载 \(snapshot.name) 的本地 Patch")
    }

    private func restoreLocalSnapshot(_ snapshot: ShelveSnapshot) async {
        await viewModel?.restore(snapshot)
        if updateStatus(for: .restore, success: "已恢复 \(snapshot.name)") {
            await reloadPaths()
        }
    }

    private func deleteLocalSnapshot(_ snapshot: ShelveSnapshot) async {
        await viewModel?.delete(snapshot)
        _ = updateStatus(for: .delete, success: "已删除本地快照 \(snapshot.name)")
    }

    private func migrate(_ snapshot: ShelveSnapshot) async {
        await viewModel?.migrateToOfficial(snapshot)
        if updateStatus(for: .migrate, success: "已将 \(snapshot.name) 迁移到官方 shelf") {
            await reloadPaths()
        }
    }

    @discardableResult
    private func updateStatus(for operation: ShelveOperation, success: LocalizedStringKey) -> Bool {
        switch viewModel?.state {
        case .completed(let completed) where completed == operation:
            statusText = success
            return true
        case .error(let message):
            statusText = "操作失败：\(message)"
            return false
        default:
            return false
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
