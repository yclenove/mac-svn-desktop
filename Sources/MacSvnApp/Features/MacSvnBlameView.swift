import SwiftUI
import MacSvnCore

public struct MacSvnBlameView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession

    @State private var paths: [String] = []
    @State private var selected: Set<String> = []
    @State private var viewModel: BlameViewModel?
    @State private var differenceViewModel: BlameDifferenceViewModel?
    @State private var evolutionVM: AIBlameEvolutionViewModel?
    @State private var rangeStartText = "1"
    @State private var rangeEndText = "1"
    @State private var blameStartRevisionText = ""
    @State private var blameEndRevisionText = ""
    @State private var displayMode: BlameDisplayMode = .standard
    @State private var showOnlyDifferences = true
    @State private var statusText: String?
    @State private var externalBlameTool: ExternalDiffToolConfiguration?

    private enum BlameDisplayMode: String, CaseIterable, Identifiable {
        case standard = "Blame"
        case differences = "差异"

        var id: String { rawValue }
    }

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
                Text("Blame")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Picker("模式", selection: $displayMode) {
                    ForEach(BlameDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                TextField(displayMode == .differences ? "旧修订" : "起始修订", text: $blameStartRevisionText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                TextField(displayMode == .differences ? "新修订" : "结束修订", text: $blameEndRevisionText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                if displayMode == .differences {
                    Button("BASE") { Task { await useBaseRevision() } }
                        .disabled(selected.count != 1)
                }
                Button(displayMode == .differences ? "比较" : "加载") {
                    Task { await loadBlame() }
                }
                    .disabled(selected.count != 1)
                Button("外置 Blame") {
                    Task { await openExternalBlame() }
                }
                .disabled(selected.count != 1 || externalBlameTool == nil)
            }
            .padding(24)

            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }

            if workspaceController.selectedRecord == nil {
                ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
            } else {
                HSplitView {
                    MacSvnPathPicker(paths: paths, selection: $selected, allowsMultiple: false)
                        .frame(minWidth: 220)
                    if displayMode == .differences {
                        blameDifferenceContent
                            .frame(minWidth: 620)
                    } else {
                        blameContent
                            .frame(minWidth: 320)
                        evolutionPane
                            .frame(minWidth: 280)
                    }
                }
            }
        }
        .task {
            evolutionVM = AIBlameEvolutionViewModel(explainer: session.aiBlameEvolutionExplainer)
            await reloadPaths()
            await consumePendingBlame()
        }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await reloadPaths() }
        }
        .onChange(of: navigator.pendingBlameIntent) { _, _ in
            Task { await consumePendingBlame() }
        }
        .onChange(of: selected) { _, _ in
            Task { await refreshExternalBlameTool() }
        }
    }

    @ViewBuilder
    private var blameDifferenceContent: some View {
        if let differenceViewModel {
            switch differenceViewModel.state {
            case .loading:
                ProgressView("比较 blame…")
            case .error(let message):
                ContentUnavailableView(
                    "比较失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .loaded:
                let rows = showOnlyDifferences
                    ? differenceViewModel.changedRows
                    : differenceViewModel.rows
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        if let from = differenceViewModel.fromRevision,
                           let to = differenceViewModel.toRevision {
                            Text("r\(from.value) → r\(to.value)")
                                .font(.caption.monospaced().weight(.semibold))
                        }
                        let summary = differenceViewModel.summary
                        Text("修改 \(summary.contentModified) · 新增 \(summary.added) · 删除 \(summary.deleted) · 归属变化 \(summary.attributionChanged)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("仅变化", isOn: $showOnlyDifferences)
                            .toggleStyle(.checkbox)
                    }
                    .padding(12)
                    Divider()
                    if rows.isEmpty, differenceViewModel.diffText.isEmpty {
                        ContentUnavailableView("两个修订内容一致", systemImage: "equal.circle")
                    } else if rows.isEmpty {
                        ScrollView([.vertical, .horizontal]) {
                            Text(DiffPerformanceLimits.truncatedDisplayText(differenceViewModel.diffText))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(12)
                        }
                    } else {
                        List(rows) { row in
                            blameDifferenceRow(row)
                        }
                        .listStyle(.inset)
                    }
                }
            case .idle:
                ContentUnavailableView("选择文件与双修订", systemImage: "arrow.left.arrow.right")
            }
        } else {
            ContentUnavailableView("选择文件与双修订", systemImage: "arrow.left.arrow.right")
        }
    }

    private func blameDifferenceRow(_ row: BlameDifferenceRow) -> some View {
        HStack(alignment: .top, spacing: 0) {
            blameDifferenceCell(row.left, kind: row.kind)
            Divider()
            blameDifferenceCell(row.right, kind: row.kind)
        }
        .background(blameDifferenceBackground(row.kind))
    }

    private func blameDifferenceCell(
        _ cell: BlameDifferenceCell?,
        kind: BlameDifferenceRowKind
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let cell {
                if kind != .hunk {
                    HStack(spacing: 8) {
                        Text(cell.lineNumber.map(String.init) ?? "-")
                        Text(cell.revision.map { "r\($0.value)" } ?? "-")
                        Text(cell.author ?? "-")
                        if let date = cell.date {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                }
                Text(cell.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                Text(" ").font(.caption).opacity(0)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
    }

    private func blameDifferenceBackground(_ kind: BlameDifferenceRowKind) -> Color {
        switch kind {
        case .hunk: return Color.secondary.opacity(0.08)
        case .unchanged: return Color.clear
        case .attributionChanged: return Color.yellow.opacity(0.12)
        case .contentModified: return Color.blue.opacity(0.10)
        case .added: return Color.green.opacity(0.12)
        case .deleted: return Color.red.opacity(0.10)
        }
    }

    @ViewBuilder
    private var blameContent: some View {
        if let viewModel {
            switch viewModel.state {
            case .loading:
                ProgressView("加载 blame…")
            case .error(let message):
                Text(message).foregroundStyle(.red).padding()
            case .loaded:
                VStack(spacing: 0) {
                    List(viewModel.lines, id: \.lineNumber) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(line.lineNumber)")
                                .font(.caption.monospaced())
                                .frame(width: 40, alignment: .trailing)
                            Text(line.revision.map { "r\($0.value)" } ?? "-")
                                .font(.caption.monospaced())
                                .frame(width: 70, alignment: .leading)
                            Text(line.author ?? "")
                                .font(.caption)
                                .frame(width: 100, alignment: .leading)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .background(
                            isLineInSelectedRange(line.lineNumber)
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                        )
                        .onHover { hovering in
                            Task {
                                if hovering {
                                    await viewModel.loadRevisionDetails(for: line.lineNumber)
                                } else {
                                    viewModel.clearRevisionDetails(for: line.lineNumber)
                                }
                            }
                        }
                        .onTapGesture {
                            viewModel.selectLine(line.lineNumber)
                            rangeStartText = "\(line.lineNumber)"
                            rangeEndText = "\(line.lineNumber)"
                            applyRangeToEvolutionVM()
                        }
                    }
                    if viewModel.hoveredLineNumber != nil {
                        Divider()
                        blameHoverLog(viewModel)
                    }
                }
            default:
                ContentUnavailableView("选择文件", systemImage: "doc.text")
            }
        } else {
            ContentUnavailableView("选择文件后点击加载", systemImage: "doc.text.magnifyingglass")
        }
    }

    @ViewBuilder
    private func blameHoverLog(_ viewModel: BlameViewModel) -> some View {
        if let entry = viewModel.hoveredLog {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("r\(entry.revision.value)").font(.caption.monospaced().weight(.semibold))
                    Text(entry.author).font(.caption)
                    if let date = entry.date {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(entry.message.isEmpty ? "（无日志说明）" : entry.message)
                    .font(.caption)
                    .lineLimit(3)
                    .textSelection(.enabled)
                if !entry.changedPaths.isEmpty {
                    Text(entry.changedPaths.prefix(4).map { "\($0.action.rawValue) \($0.path)" }.joined(separator: " · "))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let error = viewModel.hoverLogError {
            Text("日志加载失败：\(error)").font(.caption).foregroundStyle(.red).padding(10)
        } else {
            ProgressView("加载 revision 日志…").padding(10)
        }
    }

    private var evolutionPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI 演化解释")
                .font(.headline)
            Text("选择行范围后生成该区段的 revision 演化说明（FR-AI-06）。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("起始行", text: $rangeStartText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("–")
                TextField("结束行", text: $rangeEndText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("应用") { applyRangeToEvolutionVM() }
            }

            Button(evolutionVM?.state == .explaining ? "解释中…" : "AI 解释选区") {
                Task { await runEvolutionExplain() }
            }
            .disabled(
                viewModel?.state != .loaded
                    || evolutionVM?.state == .explaining
                    || selected.count != 1
            )

            if case .error(let message) = evolutionVM?.state {
                Text(message).foregroundStyle(.red).font(.caption)
            }

            if let explanation = evolutionVM?.explanation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(explanation.summary)
                            .font(.body)
                            .textSelection(.enabled)
                        ForEach(explanation.keyChanges, id: \.revision.value) { change in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("r\(change.revision.value) · \(change.title)")
                                    .font(.caption.weight(.semibold))
                                Text(change.explanation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        Text("证据 revision：\(explanation.evidenceRevisionCount)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Spacer()
            }
        }
        .padding()
    }

    private func isLineInSelectedRange(_ lineNumber: Int) -> Bool {
        guard let range = evolutionVM?.selectedLineRange else { return false }
        return range.contains(lineNumber)
    }

    private func applyRangeToEvolutionVM() {
        let start = Int(rangeStartText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
        let end = Int(rangeEndText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? start
        evolutionVM?.setRange(start: start, end: end)
        rangeStartText = "\(evolutionVM?.rangeStart ?? start)"
        rangeEndText = "\(evolutionVM?.rangeEnd ?? end)"
    }

    private func reloadPaths() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            paths = []; selected = []; viewModel = nil; return
        }
        paths = await MacSvnPathLoader.loadPaths(
            svnService: session.svnService,
            wc: URL(fileURLWithPath: record.localPath)
        )
        await refreshExternalBlameTool()
    }

    /// 消费历史页 L03/L07 或命令面板注入的 Blame 路径与修订。
    private func consumePendingBlame() async {
        guard let intent = navigator.consumePendingBlameIntent() else { return }
        let path = intent.path
        if !path.isEmpty {
            if !paths.contains(path) {
                paths.insert(path, at: 0)
            }
            selected = [path]
        }
        switch intent.mode {
        case .standard:
            displayMode = .standard
            if let revision = intent.revision {
                blameEndRevisionText = "\(revision.value)"
            }
        case .differences:
            displayMode = .differences
            blameStartRevisionText = intent.fromRevision.map { "\($0.value)" } ?? ""
            blameEndRevisionText = intent.toRevision.map { "\($0.value)" } ?? ""
        }
        statusText = path.isEmpty ? "比较修订" : "来自历史：\(path)"
        if selected.count == 1,
           intent.mode == .standard || (intent.fromRevision != nil && intent.toRevision != nil) {
            await loadBlame()
        }
    }

    private func loadBlame() async {
        if displayMode == .differences {
            await loadBlameDifferences()
            return
        }
        guard let record = workspaceController.selectedRecord,
              let path = selected.first
        else { return }
        let vm = BlameViewModel(
            workingCopy: URL(fileURLWithPath: record.localPath),
            target: path,
            provider: session.svnService,
            logProvider: session.svnService,
            rangeProvider: session.svnService
        )
        viewModel = vm
        guard let revisionRange = parsedBlameRevisionRange() else { return }
        await vm.load(startRevision: revisionRange.start, endRevision: revisionRange.end)
        if case .loaded = vm.state, let first = vm.lines.first?.lineNumber, let last = vm.lines.last?.lineNumber {
            rangeStartText = "\(first)"
            rangeEndText = "\(min(first + 9, last))"
            applyRangeToEvolutionVM()
            statusText = "已加载 \(vm.lines.count) 行"
        } else if case .error(let message) = vm.state {
            statusText = message
        }
    }

    private func loadBlameDifferences() async {
        guard let record = workspaceController.selectedRecord,
              let path = selected.first
        else { return }
        let oldText = blameStartRevisionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let newText = blameEndRevisionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let oldValue = Int(oldText), oldValue > 0,
              let newValue = Int(newText), newValue > 0 else {
            statusText = "比较修订必须是正整数"
            return
        }
        let vm = BlameDifferenceViewModel(
            workingCopy: URL(fileURLWithPath: record.localPath),
            target: path,
            provider: session.svnService
        )
        differenceViewModel = vm
        await vm.load(from: Revision(oldValue), to: Revision(newValue))
        switch vm.state {
        case .loaded:
            statusText = "已比较 r\(oldValue)–r\(newValue)，发现 \(vm.changedRows.count) 行变化"
        case .error(let message):
            statusText = message
        default:
            break
        }
    }

    private func useBaseRevision() async {
        guard let record = workspaceController.selectedRecord,
              let path = selected.first else { return }
        do {
            let info = try await session.svnService.info(
                wc: URL(fileURLWithPath: record.localPath),
                target: path
            )
            guard let revision = info.revision else {
                statusText = "当前目标没有可用 BASE 修订"
                return
            }
            let currentOld = Int(blameStartRevisionText.trimmingCharacters(in: .whitespacesAndNewlines))
            let currentNew = Int(blameEndRevisionText.trimmingCharacters(in: .whitespacesAndNewlines))
            if let currentOld, currentOld < revision.value {
                blameEndRevisionText = "\(revision.value)"
            } else if let currentNew, currentNew < revision.value {
                blameStartRevisionText = "\(currentNew)"
                blameEndRevisionText = "\(revision.value)"
            } else {
                blameEndRevisionText = "\(revision.value)"
            }
            statusText = "已将 BASE r\(revision.value) 设为新修订"
        } catch {
            statusText = "读取 BASE 失败：\(error.localizedDescription)"
        }
    }

    private func parsedBlameRevisionRange() -> (start: Revision?, end: Revision?)? {
        let startText = blameStartRevisionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let endText = blameEndRevisionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = startText.isEmpty ? nil : Int(startText).flatMap { $0 > 0 ? Revision($0) : nil }
        let end = endText.isEmpty ? nil : Int(endText).flatMap { $0 > 0 ? Revision($0) : nil }

        if (!startText.isEmpty && start == nil) || (!endText.isEmpty && end == nil) {
            statusText = "Blame 修订号必须是正整数"
            return nil
        }
        if let start, let end, start.value > end.value {
            statusText = "Blame 起始修订不能大于结束修订"
            return nil
        }
        return (start, end)
    }

    private func refreshExternalBlameTool() async {
        let settings = await session.settingsStore.settings()
        externalBlameTool = ExternalToolRuleResolver.tool(
            for: .blame,
            path: selected.first ?? "",
            rules: settings.externalToolRules,
            legacyDiffTool: settings.externalDiffTool
        )
    }

    private func openExternalBlame() async {
        guard let record = workspaceController.selectedRecord,
              let path = selected.first else { return }
        let settings = await session.settingsStore.settings()
        guard let tool = ExternalToolRuleResolver.tool(
            for: .blame,
            path: path,
            rules: settings.externalToolRules,
            legacyDiffTool: settings.externalDiffTool
        ) else {
            statusText = "请先在设置中配置此扩展名的外置 Blame 工具。"
            return
        }
        externalBlameTool = tool
        do {
            _ = try await ExternalToolLaunchService(timeout: settings.processTimeout).openBlame(
                wc: URL(fileURLWithPath: record.localPath),
                target: path,
                tool: tool
            )
            statusText = "已打开外置 Blame（\(tool.name)）"
        } catch {
            statusText = "外置 Blame 失败：\(error.localizedDescription)"
        }
    }

    private func runEvolutionExplain() async {
        guard let record = workspaceController.selectedRecord,
              let path = selected.first,
              let viewModel,
              let evolutionVM
        else { return }
        applyRangeToEvolutionVM()
        let privacy = await session.currentAIPrivacy()
        await evolutionVM.explain(
            wc: URL(fileURLWithPath: record.localPath),
            target: path,
            blameLines: viewModel.lines,
            privacySettings: privacy
        )
        switch evolutionVM.state {
        case .completed(let explanation):
            statusText = "演化解释完成（\(explanation.keyChanges.count) 个关键变更）"
        case .error(let message):
            statusText = "演化解释失败：\(message)"
        default:
            break
        }
    }
}
