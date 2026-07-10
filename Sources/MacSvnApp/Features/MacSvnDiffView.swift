import SwiftUI
import MacSvnCore

/// Diff 页：Unified / Side-by-side；支持两 revision 对比（FR-DF-02/03）。
public struct MacSvnDiffView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession
    private let embedded: Bool
    @Binding private var externalSelectedPath: String?

    @State private var paths: [String] = []
    @State private var selectedPath: String?
    @State private var viewModel: DiffViewModel?
    @State private var errorText: String?
    @State private var mode: DiffMode = .unified
    @State private var r1Text = ""
    @State private var r2Text = ""

    private enum DiffMode: String, CaseIterable, Identifiable {
        case unified = "Unified"
        case sideBySide = "左右分栏"
        var id: String { rawValue }
    }

    public init(
        workspaceController: MacSvnWorkspaceController,
        session: MacSvnAppSession,
        navigator: MacSvnAppNavigator,
        embedded: Bool = false,
        externalSelectedPath: Binding<String?> = .constant(nil)
    ) {
        self.workspaceController = workspaceController
        self.session = session
        self.navigator = navigator
        self.embedded = embedded
        _externalSelectedPath = externalSelectedPath
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(embedded ? "差异" : "Diff")
                    .font(embedded ? .headline : .largeTitle.weight(.semibold))
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(DiffMode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                if !embedded {
                    TextField("r1", text: $r1Text)
                        .frame(width: 72)
                        .textFieldStyle(.roundedBorder)
                    TextField("r2", text: $r2Text)
                        .frame(width: 72)
                        .textFieldStyle(.roundedBorder)
                    Button("按 revision 加载") {
                        Task { await reloadSelected() }
                    }
                    Button("刷新文件列表") {
                        Task { await reloadPaths() }
                    }
                } else {
                    Button("刷新") {
                        Task { await reloadSelected() }
                    }
                }
            }
            .padding(embedded ? 12 : 24)

            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .padding(.horizontal, embedded ? 12 : 24)
            }

            if workspaceController.selectedRecord == nil {
                ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
            } else if embedded {
                diffContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onChange(of: externalSelectedPath) { _, newValue in
            guard embedded else { return }
            if let newValue {
                Task { await loadExternalPath(newValue) }
            } else {
                selectedPath = nil
                // 保留 viewModel 实例，仅清空展示，避免反复重建 Observable
                viewModel?.clearDisplay()
            }
        }
        .task {
            if embedded {
                await ensureViewModel()
                await consumeNavigatorIntent()
                if let externalSelectedPath {
                    await loadExternalPath(externalSelectedPath)
                }
            } else {
                await reloadPaths()
                await consumeNavigatorIntent()
            }
        }
        .onChange(of: navigator.pendingDiffPath) { _, _ in
            Task { await consumeNavigatorIntent() }
        }
        .onChange(of: navigator.pendingDiffRevision) { _, _ in
            Task { await consumeNavigatorIntent() }
        }
    }

    private func loadExternalPath(_ path: String) async {
        await ensureViewModel()
        if selectedPath == path, viewModel?.state == .loaded {
            return
        }
        if !paths.contains(path) {
            paths.insert(path, at: 0)
        }
        selectedPath = path
        await loadDiff(path: path)
    }

    private func ensureViewModel() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            viewModel = nil
            return
        }
        if viewModel == nil {
            let wc = URL(fileURLWithPath: record.localPath)
            viewModel = DiffViewModel(workingCopy: wc, diffProvider: session.svnService)
        }
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
                if DiffPerformanceLimits.shouldUsePerLineSwiftUI(
                    lineOrRowCount: viewModel.sideBySideRows.count,
                    embedded: embedded
                ), mode == .sideBySide {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(viewModel.sideBySideRows) { row in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(row.left?.text ?? "")
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(4)
                                        .background(sideBackground(row.left?.kind))
                                    Text(row.right?.text ?? "")
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(4)
                                        .background(sideBackground(row.right?.kind))
                                }
                            }
                        }
                        .padding(12)
                    }
                } else if DiffPerformanceLimits.shouldUsePerLineSwiftUI(
                    lineOrRowCount: viewModel.lines.count,
                    embedded: embedded
                ), mode == .unified {
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
                } else {
                    // 嵌入工作区 / 超大 Diff：单块文本，避免 AttributeGraph 死循环
                    ScrollView([.vertical, .horizontal]) {
                        Text(DiffPerformanceLimits.truncatedDisplayText(viewModel.diffText))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(12)
                    }
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
            let statuses = try await session.svnService.status(wc: wc)
            paths = statuses.map(\.path).sorted()
            viewModel = DiffViewModel(
                workingCopy: wc,
                diffProvider: session.svnService
            )
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

    private func reloadSelected() async {
        guard let selectedPath else { return }
        await loadDiff(path: selectedPath)
    }

    private func loadDiff(path: String) async {
        guard let viewModel else { return }
        let r1 = Int(r1Text).map { Revision($0) }
        let r2 = Int(r2Text).map { Revision($0) }
        await viewModel.load(target: path, r1: r1, r2: r2)
    }

    private func consumeNavigatorIntent() async {
        if let rev = navigator.consumePendingDiffRevision() {
            r1Text = String(max(0, rev.value - 1))
            r2Text = String(rev.value)
        }
        if let path = navigator.consumePendingDiffPath() {
            if !paths.contains(path) {
                paths.insert(path, at: 0)
            }
            selectedPath = path
            await loadDiff(path: path)
        } else if !r1Text.isEmpty || !r2Text.isEmpty, let selectedPath {
            await loadDiff(path: selectedPath)
        }
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

    private func sideBackground(_ kind: SideBySideDiffCellKind?) -> Color {
        switch kind {
        case .addition: return Color.green.opacity(0.12)
        case .deletion: return Color.red.opacity(0.12)
        case .modified: return Color.yellow.opacity(0.12)
        default: return Color.clear
        }
    }
}
