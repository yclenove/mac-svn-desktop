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
    @State private var comparePath = ""
    @State private var viewModel: DiffViewModel?
    @State private var errorText: String?
    @State private var statusText: String?
    @State private var mode: DiffMode = .unified
    @State private var r1Text = ""
    @State private var r2Text = ""
    @State private var urlDiffTarget = ""
    @State private var urlDiffURL = ""
    @State private var urlDiffRevision = ""
    @State private var showURLDiffSheet = false
    @State private var externalDiffTool: ExternalDiffToolConfiguration?

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
                if !embedded {
                    diffModePicker
                        .frame(maxWidth: 220)
                    TextField("r1", text: $r1Text)
                        .frame(width: 72)
                        .textFieldStyle(.roundedBorder)
                    TextField("r2", text: $r2Text)
                        .frame(width: 72)
                        .textFieldStyle(.roundedBorder)
                    Button("按 revision 加载") {
                        Task { await reloadSelected() }
                    }
                    Button("对比 BASE") {
                        Task { await loadAgainstBase() }
                    }
                    TextField("对比文件", text: $comparePath)
                        .frame(width: 120)
                        .textFieldStyle(.roundedBorder)
                        .help("填写第二路径后点「双文件 Diff」")
                    Button("双文件 Diff") {
                        Task { await loadTwoFiles() }
                    }
                    .disabled(selectedPath == nil || comparePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("与 URL 比较…") {
                        prepareURLDiff()
                    }
                    Button("外置查看器") {
                        Task { await openExternal() }
                    }
                    .disabled(selectedPath == nil || externalDiffTool == nil)
                    Button("刷新文件列表") {
                        Task { await reloadPaths() }
                    }
                } else {
                    diffModePicker
                        .frame(width: 160)
                    Button("对比 BASE") {
                        Task { await loadAgainstBase() }
                    }
                    .disabled(selectedPath == nil)
                    Button("与 URL 比较…") {
                        prepareURLDiff()
                    }
                    Button("外置") {
                        Task { await openExternal() }
                    }
                    .disabled(selectedPath == nil || externalDiffTool == nil)
                    Button("刷新") {
                        Task { await reloadSelected() }
                    }
                }
            }
            .padding(embedded ? 12 : 24)

            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, embedded ? 12 : 24)
            }

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
                        Task {
                            await refreshExternalTool(for: newValue)
                            await loadDiff(path: newValue)
                        }
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
            // 历史原子 Diff 由 pendingLogDiff 路径处理，避免先按 BASE 加载
            if navigator.pendingLogDiff != nil { return }
            if let newValue {
                Task { await loadExternalPath(newValue, resetRevisionRange: true) }
            } else {
                selectedPath = nil
                // 保留 viewModel 实例，仅清空展示，避免反复重建 Observable
                viewModel?.clearDisplay()
            }
        }
        .task {
            await refreshExternalTool()
            if embedded {
                await ensureViewModel()
                await consumeNavigatorIntent()
                if navigator.pendingLogDiff == nil, let externalSelectedPath {
                    await loadExternalPath(externalSelectedPath, resetRevisionRange: false)
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
        .onChange(of: navigator.pendingLogDiff) { _, _ in
            Task { await consumeNavigatorIntent() }
        }
        .onChange(of: navigator.pendingDiffWithURL) { _, _ in
            Task { await consumeNavigatorIntent() }
        }
        .sheet(isPresented: $showURLDiffSheet) {
            urlDiffSheet
        }
    }

    private func loadExternalPath(_ path: String, resetRevisionRange: Bool) async {
        await ensureViewModel()
        if resetRevisionRange {
            // CFM 切换文件：回到 WC/BASE，避免沿用历史页修订窗口
            r1Text = ""
            r2Text = ""
        }
        if !paths.contains(path) {
            paths.insert(path, at: 0)
        }
        selectedPath = path
        await loadDiff(path: path)
    }

    private func embeddedSideBySideContent(_ viewModel: DiffViewModel) -> some View {
        let columns = DiffViewModel.sideBySideColumnTexts(viewModel.sideBySideRows)
        return ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 0) {
                ScrollView(.horizontal) {
                    Text(columns.left)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
                Divider()
                ScrollView(.horizontal) {
                    Text(columns.right)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
            }
        }
    }

    private func ensureViewModel() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            viewModel = nil
            return
        }
        if viewModel == nil {
            viewModel = makeDiffViewModel(wc: URL(fileURLWithPath: record.localPath))
        }
    }

    private func makeDiffViewModel(wc: URL) -> DiffViewModel {
        DiffViewModel(
            workingCopy: wc,
            diffProvider: session.svnService,
            externalDiffOpener: ExternalDiffService(
                contentProvider: session.svnService,
                runner: ProcessRunner()
            )
        )
    }

    private func refreshExternalTool(for path: String? = nil) async {
        let settings = await session.settingsStore.settings()
        externalDiffTool = ExternalToolRuleResolver.tool(
            for: .diff,
            path: path ?? selectedPath ?? "",
            rules: settings.externalToolRules,
            legacyDiffTool: settings.externalDiffTool
        )
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
                if embedded, mode == .sideBySide,
                   DiffPerformanceLimits.shouldUseEmbeddedSideBySide(
                       rowCount: viewModel.sideBySideRows.count
                   ) {
                    embeddedSideBySideContent(viewModel)
                } else if DiffPerformanceLimits.shouldUsePerLineSwiftUI(
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
            viewModel = makeDiffViewModel(wc: wc)
            errorText = nil
            if let selectedPath, paths.contains(selectedPath) {
                await refreshExternalTool(for: selectedPath)
                await loadDiff(path: selectedPath)
            } else {
                selectedPath = paths.first
                if let selectedPath {
                    await refreshExternalTool(for: selectedPath)
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
        // 未填 revision 时默认 WC vs BASE
        await viewModel.load(target: path, r1: r1, r2: r2)
        statusText = (r1 == nil && r2 == nil) ? "对比 BASE（工作副本）" : "对比 r\(r1Text)–r\(r2Text)"
    }

    private func loadAgainstBase() async {
        guard let viewModel, let selectedPath else { return }
        r1Text = ""
        r2Text = ""
        await viewModel.loadAgainstBase(target: selectedPath)
        statusText = "对比 BASE"
    }

    private func loadTwoFiles() async {
        guard let viewModel, let selectedPath else { return }
        let other = comparePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !other.isEmpty else { return }
        await viewModel.loadBetweenPaths(oldPath: selectedPath, newPath: other)
        statusText = "双文件：\(selectedPath) ↔ \(other)"
    }

    private func openExternal() async {
        guard let viewModel, let selectedPath else { return }
        await refreshExternalTool(for: selectedPath)
        guard let tool = externalDiffTool else {
            errorText = "请先在设置中配置外置 Diff 工具"
            return
        }
        let r1 = Int(r1Text).map { Revision($0) }
        let r2 = Int(r2Text).map { Revision($0) }
        await viewModel.openExternalDiff(target: selectedPath, tool: tool, r1: r1, r2: r2)
        switch viewModel.externalDiffState {
        case .opened:
            statusText = "已打开外置 Diff（\(tool.name)）"
            errorText = nil
        case .error(let message):
            errorText = "外置 Diff 失败：\(message)"
        default:
            break
        }
    }

    private var diffModePicker: some View {
        Picker("显示模式", selection: $mode) {
            ForEach(DiffMode.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    private var urlDiffSheet: some View {
        NavigationStack {
            Form {
                TextField("本地目标", text: $urlDiffTarget)
                TextField("仓库 URL", text: $urlDiffURL)
                    .textContentType(.URL)
                TextField("Revision（留空为 HEAD）", text: $urlDiffRevision)
            }
            .formStyle(.grouped)
            .navigationTitle("与 URL 比较")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showURLDiffSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("比较") {
                        showURLDiffSheet = false
                        Task { await loadURLDiff() }
                    }
                    .disabled(
                        urlDiffTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        urlDiffURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
        .frame(minWidth: 420, minHeight: 220)
    }

    private func prepareURLDiff() {
        urlDiffTarget = selectedPath ?? externalSelectedPath ?? ""
        urlDiffURL = ""
        urlDiffRevision = ""
        showURLDiffSheet = true
    }

    private func loadURLDiff() async {
        await ensureViewModel()
        guard let viewModel else {
            errorText = "请先选择有效工作副本"
            showURLDiffSheet = true
            return
        }
        await viewModel.loadWithURL(
            target: urlDiffTarget,
            url: urlDiffURL,
            revisionText: urlDiffRevision
        )
        switch viewModel.state {
        case .loaded:
            statusText = "与 URL 比较：\(urlDiffURL)"
            errorText = nil
        case .error(let message):
            errorText = "URL Diff 失败：\(message)"
        default:
            break
        }
    }

    private func consumeNavigatorIntent() async {
        if let intent = navigator.consumePendingDiffWithURL() {
            urlDiffTarget = intent.target ?? selectedPath ?? externalSelectedPath ?? ""
            urlDiffURL = intent.url ?? ""
            urlDiffRevision = intent.revision.map(String.init) ?? ""
            if urlDiffTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                urlDiffURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showURLDiffSheet = true
            } else {
                await loadURLDiff()
            }
            return
        }
        if let intent = navigator.consumePendingLogDiff() {
            switch intent.kind {
            case .previous:
                r1Text = String(max(0, intent.revision.value - 1))
                r2Text = String(intent.revision.value)
            case .workingCopy:
                r1Text = String(intent.revision.value)
                r2Text = ""
            }
            await loadExternalPath(intent.path, resetRevisionRange: false)
            return
        }

        var revisionApplied = false
        if let rev = navigator.consumePendingDiffRevision() {
            let kind = navigator.consumePendingDiffCompareKind()
            switch kind {
            case .previous:
                r1Text = String(max(0, rev.value - 1))
                r2Text = String(rev.value)
            case .workingCopy:
                r1Text = String(rev.value)
                r2Text = ""
            }
            revisionApplied = true
        }
        // 嵌入模式由 WorkingCopyWorkspace 消费 pendingDiffPath 并经 externalSelectedPath 注入
        if embedded {
            // 分字段修订后到：对当前嵌入路径按 r1:r2 重载
            if revisionApplied, let path = externalSelectedPath ?? selectedPath {
                await loadDiff(path: path)
            }
            return
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
