import SwiftUI
import MacSvnCore

/// 冲突工作区：列表 + 文本三路合并 / 树冲突解决；并保留 Merge 向导入口。
public struct MacSvnConflictWorkspaceView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let session: MacSvnAppSession

    @State private var tab: Tab = .conflicts
    @State private var listVM: ConflictListViewModel?
    @State private var editorVM: MergeEditorViewModel?
    @State private var treeVM: TreeConflictViewModel?
    @State private var statusText: String?
    @State private var conflictBadgeCount = 0

    private enum Tab: String, CaseIterable, Identifiable {
        case conflicts = "冲突列表"
        case mergeWizard = "合并向导"
        var id: String { rawValue }
    }

    public init(workspaceController: MacSvnWorkspaceController, session: MacSvnAppSession) {
        self.workspaceController = workspaceController
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("冲突合并")
                    .font(.largeTitle.weight(.semibold))
                if conflictBadgeCount > 0 {
                    Text("\(conflictBadgeCount)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.85))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                Spacer()
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                Button("刷新冲突") {
                    Task { await reloadConflicts() }
                }
            }
            .padding(24)

            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }

            switch tab {
            case .conflicts:
                conflictPane
            case .mergeWizard:
                MacSvnMergeWizardView(workspaceController: workspaceController, session: session)
            }
        }
        .task { await reloadConflicts() }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await reloadConflicts() }
        }
    }

    @ViewBuilder
    private var conflictPane: some View {
        if workspaceController.selectedRecord == nil {
            ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
        } else if let listVM {
            HSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("共 \(listVM.summary.total)（文本 \(listVM.summary.text) / 树 \(listVM.summary.tree)）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                    List(selection: Binding(
                        get: { listVM.selectedConflictPath },
                        set: { path in
                            if let path {
                                listVM.selectConflict(path: path)
                            }
                            Task { await openSelected() }
                        }
                    )) {
                        ForEach(listVM.visibleConflicts, id: \.path) { conflict in
                            HStack {
                                Text(kindLabel(conflict.kind))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(kindColor(conflict.kind))
                                    .frame(width: 36, alignment: .leading)
                                Text(conflict.path)
                            }
                            .tag(conflict.path)
                        }
                    }
                }
                .frame(minWidth: 260)

                detailPane
                    .frame(minWidth: 420)
            }
        } else {
            ProgressView("扫描冲突…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let conflict = listVM?.selectedConflict {
            switch conflict.kind {
            case .text:
                MacSvnMergeEditorPane(editorVM: editorVM, statusText: $statusText) {
                    Task { await reloadConflicts() }
                }
            case .tree:
                MacSvnTreeConflictPane(treeVM: treeVM) {
                    Task { await reloadConflicts() }
                }
            default:
                ContentUnavailableView(
                    "暂不支持的冲突类型",
                    systemImage: "exclamationmark.triangle",
                    description: Text("\(conflict.kind) — \(conflict.path)")
                )
            }
        } else {
            ContentUnavailableView("无冲突", systemImage: "checkmark.seal", description: Text("当前工作副本没有待处理冲突"))
        }
    }

    private func reloadConflicts() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            listVM = nil
            editorVM = nil
            treeVM = nil
            conflictBadgeCount = 0
            return
        }
        let wc = URL(fileURLWithPath: record.localPath)
        let list = ConflictListViewModel(workingCopy: wc, provider: session.conflictService)
        listVM = list
        editorVM = MergeEditorViewModel(provider: session.conflictService)
        await list.refresh()
        conflictBadgeCount = list.summary.total
        if case .error(let message) = list.state {
            statusText = message
        } else {
            statusText = list.summary.total == 0 ? "无冲突" : "发现 \(list.summary.total) 个冲突"
            await openSelected()
        }
    }

    private func openSelected() async {
        guard let conflict = listVM?.selectedConflict,
              let record = workspaceController.selectedRecord
        else { return }
        let wc = URL(fileURLWithPath: record.localPath)
        switch conflict.kind {
        case .text:
            await editorVM?.load(conflict: conflict, wc: wc)
        case .tree:
            treeVM = TreeConflictViewModel(
                conflict: conflict,
                workingCopy: wc,
                resolver: session.conflictService
            )
        default:
            break
        }
    }

    private func kindLabel(_ kind: ConflictKind) -> String {
        switch kind {
        case .text: return "TXT"
        case .tree: return "TREE"
        case .property: return "PROP"
        case .unknown: return "?"
        }
    }

    private func kindColor(_ kind: ConflictKind) -> Color {
        switch kind {
        case .text: return .red
        case .tree: return .orange
        case .property: return .purple
        case .unknown: return .secondary
        }
    }
}

private struct MacSvnMergeEditorPane: View {
    let editorVM: MergeEditorViewModel?
    @Binding var statusText: String?
    let onSaved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let editorVM {
                HStack {
                    Button("上一处") { editorVM.previousConflict() }
                    Button("下一处") { editorVM.nextConflict() }
                    Divider()
                    Button("采用 Mine") { editorVM.resolveCurrent(.takeMine) }
                    Button("采用 Theirs") { editorVM.resolveCurrent(.takeTheirs) }
                    Button("双方(Mine先)") { editorVM.resolveCurrent(.takeBoth(mineFirst: true)) }
                    Divider()
                    Button("整文件 Mine") { Task { await editorVM.resolveWholeFileMine(); handleSaveState(editorVM) } }
                    Button("整文件 Theirs") { Task { await editorVM.resolveWholeFileTheirs(); handleSaveState(editorVM) } }
                    Spacer()
                    Text("未解决 \(editorVM.unresolvedConflictCount)")
                        .foregroundStyle(editorVM.unresolvedConflictCount == 0 ? .green : .orange)
                    Button("保存并 Resolve") {
                        Task {
                            await editorVM.saveResolved()
                            handleSaveState(editorVM)
                        }
                    }
                    .disabled(!editorVM.canSaveResolved)
                    .keyboardShortcut(.defaultAction)
                }

                switch editorVM.state {
                case .loading, .saving:
                    ProgressView()
                case .error(let message):
                    Text(message).foregroundStyle(.red)
                case .saved:
                    Text("已解决并写回").foregroundStyle(.green)
                case .loaded, .idle:
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(editorVM.blocks.enumerated()), id: \.offset) { index, block in
                                blockView(index: index, block: block, editorVM: editorVM)
                            }
                        }
                        .padding()
                    }
                }
            } else {
                ProgressView()
            }
        }
        .padding()
    }

    @ViewBuilder
    private func blockView(index: Int, block: MergeBlock, editorVM: MergeEditorViewModel) -> some View {
        switch block {
        case .stable(let lines):
            Text(lines.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.secondary.opacity(0.08))
        case .conflict(let hunk):
            VStack(alignment: .leading, spacing: 6) {
                Text("冲突块 #\(index) \(hunk.resolution == nil ? "未解决" : "已解决")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hunk.resolution == nil ? .red : .green)
                HStack(alignment: .top, spacing: 8) {
                    pane("Mine", hunk.mineLines, .blue)
                    pane("Base", hunk.baseLines, .secondary)
                    pane("Theirs", hunk.theirsLines, .orange)
                }
            }
            .padding(8)
            .background((hunk.resolution == nil ? Color.red : Color.green).opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(editorVM.currentBlockIndex == index ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
    }

    private func pane(_ title: String, _ lines: [String], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(color)
            Text(lines.joined(separator: "\n"))
                .font(.system(.caption2, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .background(color.opacity(0.08))
    }

    private func handleSaveState(_ editorVM: MergeEditorViewModel) {
        switch editorVM.state {
        case .saved:
            statusText = "冲突已 resolve"
            onSaved()
        case .error(let message):
            statusText = message
        default:
            break
        }
    }
}

private struct MacSvnTreeConflictPane: View {
    let treeVM: TreeConflictViewModel?
    let onResolved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let treeVM {
                Text(treeVM.path)
                    .font(.headline)
                LabeledContent("operation", value: treeVM.operation ?? "-")
                LabeledContent("action", value: treeVM.action ?? "-")
                LabeledContent("reason", value: treeVM.reason ?? "-")
                HStack {
                    Button("保留本地") {
                        Task {
                            await treeVM.resolve(.keepLocal)
                            if case .resolved = treeVM.state { onResolved() }
                        }
                    }
                    Button("接受远端") {
                        Task {
                            await treeVM.resolve(.acceptRemote)
                            if case .resolved = treeVM.state { onResolved() }
                        }
                    }
                }
                if case .error(let message) = treeVM.state {
                    Text(message).foregroundStyle(.red)
                }
                if case .resolved = treeVM.state {
                    Text("树冲突已处理").foregroundStyle(.green)
                }
            } else {
                ProgressView()
            }
            Spacer()
        }
        .padding()
    }
}
