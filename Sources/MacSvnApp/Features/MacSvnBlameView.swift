import SwiftUI
import MacSvnCore

public struct MacSvnBlameView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let session: MacSvnAppSession

    @State private var paths: [String] = []
    @State private var selected: Set<String> = []
    @State private var viewModel: BlameViewModel?

    public init(workspaceController: MacSvnWorkspaceController, session: MacSvnAppSession) {
        self.workspaceController = workspaceController
        self.session = session
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

            if workspaceController.selectedRecord == nil {
                ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
            } else {
                HSplitView {
                    MacSvnPathPicker(paths: paths, selection: $selected, allowsMultiple: false)
                        .frame(minWidth: 220)
                    blameContent
                }
            }
        }
        .task { await reloadPaths() }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await reloadPaths() }
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
                    .onTapGesture { viewModel.selectLine(line.lineNumber) }
                }
            default:
                ContentUnavailableView("选择文件", systemImage: "doc.text")
            }
        } else {
            ContentUnavailableView("选择文件后点击加载", systemImage: "doc.text.magnifyingglass")
        }
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
    }
}
