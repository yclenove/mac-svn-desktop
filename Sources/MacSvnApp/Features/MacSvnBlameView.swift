import SwiftUI
import MacSvnCore

public struct MacSvnBlameView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession

    @State private var paths: [String] = []
    @State private var selected: Set<String> = []
    @State private var viewModel: BlameViewModel?
    @State private var evolutionVM: AIBlameEvolutionViewModel?
    @State private var rangeStartText = "1"
    @State private var rangeEndText = "1"
    @State private var statusText: String?

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
                Button("加载") { Task { await loadBlame() } }
                    .disabled(selected.count != 1)
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
                    blameContent
                        .frame(minWidth: 320)
                    evolutionPane
                        .frame(minWidth: 280)
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
        .onChange(of: navigator.pendingBlamePath) { _, _ in
            Task { await consumePendingBlame() }
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
                    .onTapGesture {
                        viewModel.selectLine(line.lineNumber)
                        rangeStartText = "\(line.lineNumber)"
                        rangeEndText = "\(line.lineNumber)"
                        applyRangeToEvolutionVM()
                    }
                }
            default:
                ContentUnavailableView("选择文件", systemImage: "doc.text")
            }
        } else {
            ContentUnavailableView("选择文件后点击加载", systemImage: "doc.text.magnifyingglass")
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
    }

    /// 消费历史页 L07 注入的 Blame 路径。
    private func consumePendingBlame() async {
        guard let path = navigator.consumePendingBlamePath() else { return }
        if !paths.contains(path) {
            paths.insert(path, at: 0)
        }
        selected = [path]
        statusText = "来自历史：\(path)"
        await loadBlame()
    }

    private func loadBlame() async {
        guard let record = workspaceController.selectedRecord,
              let path = selected.first
        else { return }
        let vm = BlameViewModel(
            workingCopy: URL(fileURLWithPath: record.localPath),
            target: path,
            provider: session.svnService
        )
        viewModel = vm
        await vm.load()
        if case .loaded = vm.state, let first = vm.lines.first?.lineNumber, let last = vm.lines.last?.lineNumber {
            rangeStartText = "\(first)"
            rangeEndText = "\(min(first + 9, last))"
            applyRangeToEvolutionVM()
            statusText = "已加载 \(vm.lines.count) 行"
        } else if case .error(let message) = vm.state {
            statusText = message
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
