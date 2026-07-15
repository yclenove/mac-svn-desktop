import SwiftUI
import MacSvnCore

/// Diff 页：Unified / Side-by-side；支持两 revision 对比（FR-DF-02/03）。
public struct MacSvnDiffView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession
    private let embedded: Bool
    @Binding private var externalSelectedPath: String?

    @State private var paths: [String] = []
    @State private var selectedPath: String?
    @State private var comparePath = ""
    @State private var viewModel: DiffViewModel?
    @State private var errorText: LocalizedStringKey?
    @State private var statusText: LocalizedStringKey?
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
            if embedded {
                embeddedToolbar
            } else {
                standaloneToolbar
            }

            if workspaceController.selectedRecord == nil {
                ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
            } else if embedded {
                embeddedDiffContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        transientErrorOverlay
                    }
            } else {
                standaloneContent
            }
        }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await handleWorkingCopyChange() }
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
                .macSvnDismissibleSheet()
        }
    }

    private var embeddedToolbar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("差异")
                    .font(.headline)
                if let selectedPath {
                    Text(selectedPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(selectedPath)
                } else {
                    Text("未选择文件")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 44, maxWidth: .infinity, alignment: .leading)

            diffModePicker
                .frame(width: 144)

            Button {
                Task { await loadAgainstBase() }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(selectedPath == nil)
            .help("与 BASE 比较")
            .accessibilityLabel("与 BASE 比较")

            Button {
                Task { await openExternal() }
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(selectedPath == nil || externalDiffTool == nil)
            .help("使用外置 Diff 查看器")
            .accessibilityLabel("使用外置 Diff 查看器")

            Button {
                Task { await reloadSelected() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(selectedPath == nil)
            .help("刷新当前差异")
            .accessibilityLabel("刷新当前差异")

            moreDiffActionsMenu
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
    }

    private var standaloneToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Diff")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                diffModePicker
                    .frame(width: 200)
                Button("对比 BASE") {
                    Task { await loadAgainstBase() }
                }
                .disabled(selectedPath == nil)
                Button("外置查看器") {
                    Task { await openExternal() }
                }
                .disabled(selectedPath == nil || externalDiffTool == nil)
                moreDiffActionsMenu
            }
            HStack(spacing: 8) {
                TextField("r1", text: $r1Text)
                    .frame(width: 72)
                    .textFieldStyle(.roundedBorder)
                TextField("r2", text: $r2Text)
                    .frame(width: 72)
                    .textFieldStyle(.roundedBorder)
                Button("按 revision 加载") {
                    Task { await reloadSelected() }
                }
                TextField("对比文件", text: $comparePath)
                    .frame(width: 180)
                    .textFieldStyle(.roundedBorder)
                Button("双文件 Diff") {
                    Task { await loadTwoFiles() }
                }
                .disabled(
                    selectedPath == nil
                        || comparePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                Spacer()
                Button("刷新文件列表") {
                    Task { await reloadPaths() }
                }
            }
            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
    }

    private var moreDiffActionsMenu: some View {
        Menu {
            Button("与 URL 比较…") {
                prepareURLDiff()
            }
            .disabled(selectedPath == nil && externalSelectedPath == nil)
            if embedded {
                Button("刷新外置工具配置") {
                    Task { await refreshExternalTool() }
                }
            }
        } label: {
            Label("更多 Diff 操作", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("更多 Diff 操作")
        .accessibilityLabel("更多 Diff 操作")
    }

    private var standaloneContent: some View {
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

    @ViewBuilder
    private var transientErrorOverlay: some View {
        if let errorText {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(errorText)
                    .font(.caption)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button {
                    self.errorText = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("关闭")
                .accessibilityLabel("关闭错误提示")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial)
            .overlay(alignment: .bottom) { Divider() }
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
    private var embeddedDiffContent: some View {
        diffPresentationContent
    }

    @ViewBuilder
    private var diffContent: some View {
        diffPresentationContent
    }

    @ViewBuilder
    private var diffPresentationContent: some View {
        let presentation = MacSvnEmbeddedDiffPresentation.resolve(
            path: selectedPath,
            state: viewModel?.state ?? .idle,
            diffText: viewModel?.diffText ?? ""
        )

        switch presentation {
        case .noSelection:
            ContentUnavailableView(
                "选择一个文件查看差异",
                systemImage: "doc.text.magnifyingglass",
                description: Text("从变更列表选择文件，提交复选框不会影响当前 Diff")
            )
        case .loading(let path):
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在加载 \((path as NSString).lastPathComponent)")
                    .font(.callout)
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .noChanges:
            ContentUnavailableView(
                "此文件没有可显示的文本差异",
                systemImage: "checkmark.circle",
                description: Text("可以尝试与 BASE、其他 URL 比较，或使用外置查看器")
            )
        case .loaded:
            if let viewModel {
                loadedDiffContent(viewModel)
            }
        case .binary(_, let details):
            ContentUnavailableView {
                Label("二进制文件", systemImage: "doc.zipper")
            } description: {
                Text(binaryDetailsDescription(details))
            } actions: {
                Button("使用外置查看器") {
                    Task { await openExternal() }
                }
                .disabled(externalDiffTool == nil)
            }
        case .error(_, let message):
            ContentUnavailableView {
                Label("无法加载差异", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                HStack {
                    Button("重试") {
                        Task { await reloadSelected() }
                    }
                    if externalDiffTool != nil {
                        Button("使用外置查看器") {
                            Task { await openExternal() }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func loadedDiffContent(_ viewModel: DiffViewModel) -> some View {
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
            // 嵌入工作区 / 超大 Diff：单块文本，避免 AttributeGraph 死循环。
            ScrollView([.vertical, .horizontal]) {
                Text(DiffPerformanceLimits.truncatedDisplayText(viewModel.diffText))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
        }
    }

    private func binaryDetailsDescription(_ details: BinaryFileDetails?) -> String {
        guard let details else { return "无法显示文本差异，请使用外置查看器" }
        var parts: [String] = ["无法显示文本差异"]
        if let size = details.size {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        if let modifiedAt = details.modifiedAt {
            parts.append(modifiedAt.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.joined(separator: " · ")
    }

    private func handleWorkingCopyChange() async {
        errorText = nil
        statusText = nil
        if embedded {
            paths = []
            selectedPath = nil
            viewModel = nil
            await ensureViewModel()
            await refreshExternalTool()
        } else {
            await reloadPaths()
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
            errorText = LocalizedStringKey(error.localizedDescription)
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
                Text(LocalizedStringKey(item.rawValue)).tag(item)
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
        let palette = session.settingsSnapshot.changeColours
        guard let role = palette.role(for: kind) else {
            return kind == .hunk || kind == .metadata ? .secondary : .primary
        }
        return svnChangeColour(palette: palette, role: role, colorScheme: colorScheme)
    }

    private func background(for kind: UnifiedDiffLineKind) -> Color {
        let palette = session.settingsSnapshot.changeColours
        guard let role = palette.role(for: kind) else { return .clear }
        return svnChangeColour(palette: palette, role: role, colorScheme: colorScheme).opacity(0.12)
    }

    private func sideBackground(_ kind: SideBySideDiffCellKind?) -> Color {
        guard let kind else { return .clear }
        let palette = session.settingsSnapshot.changeColours
        guard let role = palette.role(for: kind) else { return .clear }
        return svnChangeColour(palette: palette, role: role, colorScheme: colorScheme).opacity(0.12)
    }
}
