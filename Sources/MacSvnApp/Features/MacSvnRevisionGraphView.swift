import SwiftUI
import MacSvnCore

/// Revision Graph：远程 verbose log 驱动的分支拓扑与时间线视图。
public struct MacSvnRevisionGraphView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession

    @State private var viewModel: RevisionGraphViewModel?
    @State private var selectedNodeID: String?
    @State private var showDiffSheet = false
    @State private var statusText: LocalizedStringKey?

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
            toolbar
            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
            content
        }
        .task { await reload() }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await reload() }
        }
        .sheet(isPresented: $showDiffSheet) {
            diffSheet
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("修订图")
                .font(.title2.weight(.semibold))
            Spacer()
            if let viewModel {
                Picker("视图", selection: Binding(
                    get: { viewModel.viewMode },
                    set: { viewModel.viewMode = $0 }
                )) {
                    ForEach(RevisionGraphViewMode.allCases, id: \.self) { mode in
                        Text(mode == .topology ? "拓扑" : "时间线").tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                Toggle("标签", isOn: pruningBinding(\.includeTags))
                    .toggleStyle(.checkbox)
                Toggle("未分类", isOn: pruningBinding(\.includeUnclassified))
                    .toggleStyle(.checkbox)
                Toggle("已删除", isOn: pruningBinding(\.includeDeleted))
                    .toggleStyle(.checkbox)
                TextField("过滤路径 / 作者", text: pruningQueryBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Button("刷新", systemImage: "arrow.clockwise") {
                    Task { await reload() }
                }
                .help("重新读取仓库日志")
                Button("Next", systemImage: "chevron.down") {
                    Task { await viewModel.loadMore() }
                }
                .disabled(!viewModel.hasMore || viewModel.isLoading)
                .help("加载下一批修订")
                Button("All", systemImage: "arrow.down.to.line") {
                    Task { await viewModel.loadAll() }
                }
                .disabled(!viewModel.hasMore || viewModel.isLoading)
                .help("加载全部修订")
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if workspaceController.selectedRecord?.isValid != true {
            ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
        } else if let viewModel {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("读取仓库日志…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                ContentUnavailableView("修订图加载失败", systemImage: "exclamationmark.triangle", description: Text(message))
            case .loaded, .loadingMore:
                HStack(spacing: 0) {
                    if viewModel.viewMode == .topology {
                        topology(viewModel)
                    } else {
                        timeline(viewModel)
                    }
                    Divider()
                    detailPane(viewModel)
                        .frame(width: 300)
                }
            }
        } else {
            ProgressView("加载修订图…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func topology(_ viewModel: RevisionGraphViewModel) -> some View {
        let positioned = positionedNodes(viewModel.visibleSnapshot)
        let positions = Dictionary(uniqueKeysWithValues: positioned.map {
            ($0.node.id, CGPoint(x: $0.x + 90, y: $0.y + 32))
        })
        let width = max(640, (positioned.map(\.x).max() ?? 0) + 220)
        let height = max(500, (positioned.map(\.y).max() ?? 0) + 130)
        return ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for edge in viewModel.visibleSnapshot.edges {
                        guard let source = positions[edge.sourceID],
                              let target = positions[edge.targetID] else { continue }
                        var path = Path()
                        path.move(to: source)
                        path.addLine(to: target)
                        let style = StrokeStyle(
                            lineWidth: edge.kind == .copy ? 2 : 1.5,
                            dash: edge.kind == .copy ? [7, 5] : []
                        )
                        context.stroke(
                            path,
                            with: .color(edge.kind == .copy ? .orange : .secondary),
                            style: style
                        )
                    }
                }
                .frame(width: width, height: height)
                ForEach(positioned) { positionedNode in
                    nodeCard(positionedNode.node, viewModel: viewModel)
                        .frame(width: 180, height: 64)
                        .position(x: positionedNode.x + 90, y: positionedNode.y + 32)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func timeline(_ viewModel: RevisionGraphViewModel) -> some View {
        List(selection: $selectedNodeID) {
            ForEach(viewModel.visibleSnapshot.nodes.sorted {
                if $0.revision.value != $1.revision.value {
                    return $0.revision.value > $1.revision.value
                }
                return $0.path < $1.path
            }) { node in
                nodeRow(node, viewModel: viewModel)
                    .tag(node.id)
                    .contextMenu { nodeMenu(node, viewModel: viewModel) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nodeCard(_ node: RevisionGraphNode, viewModel: RevisionGraphViewModel) -> some View {
        Button {
            selectedNodeID = node.id
        } label: {
            nodeRow(node, viewModel: viewModel)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(nodeColor(node, viewModel: viewModel).opacity(0.12))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(nodeColor(node, viewModel: viewModel))
                        .frame(width: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu { nodeMenu(node, viewModel: viewModel) }
    }

    private func nodeRow(_ node: RevisionGraphNode, viewModel: RevisionGraphViewModel) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(nodeColor(node, viewModel: viewModel))
                .frame(width: 9, height: 9)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("r\(node.revision.value)")
                        .font(.caption.monospaced().weight(.semibold))
                    Text(categoryName(node.category))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(node.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                if !node.message.isEmpty {
                    Text(node.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func detailPane(_ viewModel: RevisionGraphViewModel) -> some View {
        if let selectedNodeID,
           let node = viewModel.visibleSnapshot.nodes.first(where: { $0.id == selectedNodeID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("节点详情")
                        .font(.headline)
                    LabeledContent("路径", value: node.path)
                    LabeledContent("修订", value: "r\(node.revision.value)")
                    LabeledContent("分类", value: categoryName(node.category))
                    if !node.author.isEmpty {
                        LabeledContent("作者", value: node.author)
                    }
                    if !node.message.isEmpty {
                        Text(node.message)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    Divider()
                    ForEach(RevisionGraphNodeAction.allCases, id: \.self) { action in
                        let intent = RevisionGraphNodeActionPolicy.intent(
                            for: action,
                            node: node,
                            repositoryRoot: viewModel.repositoryRoot
                        )
                        Button(actionTitle(action), systemImage: actionIcon(action)) {
                            perform(intent: intent, viewModel: viewModel)
                        }
                        .disabled(intent == nil || viewModel.isLoading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if case .error(let message) = viewModel.diffState {
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
        } else {
            ContentUnavailableView("选择一个节点", systemImage: "point.3.connected.trianglepath.dotted")
        }
    }

    @ViewBuilder
    private func nodeMenu(_ node: RevisionGraphNode, viewModel: RevisionGraphViewModel) -> some View {
        ForEach(RevisionGraphNodeAction.allCases, id: \.self) { action in
            let intent = RevisionGraphNodeActionPolicy.intent(
                for: action,
                node: node,
                repositoryRoot: viewModel.repositoryRoot
            )
            Button(actionTitle(action), systemImage: actionIcon(action)) {
                perform(intent: intent, viewModel: viewModel)
            }
            .disabled(intent == nil)
        }
    }

    private var diffSheet: some View {
        NavigationStack {
            ScrollView {
                Text(viewModel?.diffText ?? "")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("节点 Diff")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showDiffSheet = false }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private func reload() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            viewModel = nil
            return
        }
        let settings = await session.settingsStore.settings()
        let vm = RevisionGraphViewModel(
            workingCopy: URL(fileURLWithPath: record.localPath),
            batchSize: settings.logBatchSize,
            settings: settings.revisionGraph,
            provider: session.svnService
        )
        viewModel = vm
        selectedNodeID = nil
        await vm.loadInitial()
    }

    private func perform(intent: RevisionGraphNodeActionIntent?, viewModel: RevisionGraphViewModel) {
        guard let intent else { return }
        switch intent {
        case .log(let url, let revision):
            navigator.pendingRevisionGraphLog = PendingRevisionGraphLogIntent(url: url, revision: revision)
            navigator.selectRoute(.log)
            statusText = "打开节点日志：\(url) @ r\(revision.value)"
        case .checkout(let url, let revision):
            navigator.pendingTransferIntent = PendingTransferIntent(
                command: .checkout,
                path: nil,
                url: url,
                revision: revision,
                message: nil
            )
            navigator.selectRoute(.repositoryBrowser)
            statusText = "检出节点：\(url) @ r\(revision.value)"
        case .blame(let url, let revision):
            navigator.pendingBlameIntent = PendingBlameIntent(path: url, revision: revision)
            navigator.selectRoute(.blame)
            statusText = "Blame 节点文件：\(url) @ r\(revision.value)"
        case .diff(let nodeID):
            selectedNodeID = nodeID
            Task {
                await viewModel.loadDiff(for: nodeID)
                if viewModel.diffState == .loaded {
                    showDiffSheet = true
                }
            }
        }
    }

    private func positionedNodes(_ snapshot: RevisionGraphSnapshot) -> [PositionedRevisionGraphNode] {
        let paths = Array(Set(snapshot.nodes.map(\.path))).sorted()
        let revisions = Array(Set(snapshot.nodes.map(\.revision.value))).sorted(by: >)
        return snapshot.nodes.map { node in
            PositionedRevisionGraphNode(
                node: node,
                x: CGFloat(paths.firstIndex(of: node.path) ?? 0) * 220,
                y: CGFloat(revisions.firstIndex(of: node.revision.value) ?? 0) * 100
            )
        }
    }

    private func pruningBinding(_ keyPath: WritableKeyPath<RevisionGraphPruning, Bool>) -> Binding<Bool> {
        Binding(
            get: { viewModel?.pruning[keyPath: keyPath] ?? true },
            set: { newValue in
                guard let viewModel else { return }
                var pruning = viewModel.pruning
                pruning[keyPath: keyPath] = newValue
                viewModel.pruning = pruning
            }
        )
    }

    private var pruningQueryBinding: Binding<String> {
        Binding(
            get: { viewModel?.pruning.query ?? "" },
            set: { newValue in
                guard let viewModel else { return }
                var pruning = viewModel.pruning
                pruning.query = newValue
                viewModel.pruning = pruning
            }
        )
    }

    private func nodeColor(_ node: RevisionGraphNode, viewModel: RevisionGraphViewModel) -> Color {
        let palette = viewModel.settings.palette
        let base = Color(hex: colorHex(for: node.category, palette: palette))
        guard viewModel.settings.blendCopyColors, let source = node.sourceCategory else { return base }
        let sourceColor = Color(hex: colorHex(for: source, palette: palette))
        return Color.blended(
            colorHex(for: node.category, palette: palette),
            colorHex(for: source, palette: palette)
        ) ?? sourceColor
    }

    private func colorHex(for category: RevisionGraphNodeCategory, palette: RevisionGraphPalette) -> String {
        switch category {
        case .trunk: palette.trunkHex
        case .branch: palette.branchHex
        case .tag: palette.tagHex
        case .unclassified: palette.unclassifiedHex
        }
    }

    private func categoryName(_ category: RevisionGraphNodeCategory) -> String {
        switch category {
        case .trunk: "主干"
        case .branch: "分支"
        case .tag: "标签"
        case .unclassified: "未分类"
        }
    }

    private func actionTitle(_ action: RevisionGraphNodeAction) -> String {
        switch action {
        case .log: "日志"
        case .checkout: "检出"
        case .blame: "Blame"
        case .diff: "Diff"
        }
    }

    private func actionIcon(_ action: RevisionGraphNodeAction) -> String {
        switch action {
        case .log: "clock.arrow.circlepath"
        case .checkout: "arrow.down.to.line"
        case .blame: "person.text.rectangle"
        case .diff: "doc.text.magnifyingglass"
        }
    }
}

private struct PositionedRevisionGraphNode: Identifiable {
    let node: RevisionGraphNode
    let x: CGFloat
    let y: CGFloat
    var id: String { node.id }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let value = UInt64(cleaned, radix: 16) else {
            self = .secondary
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static func blended(_ lhs: String, _ rhs: String) -> Color? {
        let left = lhs.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let right = rhs.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let leftValue = UInt64(left, radix: 16),
              let rightValue = UInt64(right, radix: 16) else { return nil }
        let red = Double(((leftValue >> 16) & 0xFF) + ((rightValue >> 16) & 0xFF)) / 510
        let green = Double(((leftValue >> 8) & 0xFF) + ((rightValue >> 8) & 0xFF)) / 510
        let blue = Double((leftValue & 0xFF) + (rightValue & 0xFF)) / 510
        return Color(red: red, green: green, blue: blue)
    }
}
