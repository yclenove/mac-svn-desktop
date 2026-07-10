import SwiftUI
import MacSvnCore

/// ⌘K 命令面板：动作 / 文件 / 日志模糊搜索。
public struct MacSvnCommandPaletteView: View {
    @ObservedObject private var navigator: MacSvnAppNavigator
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let session: MacSvnAppSession
    @Binding private var isPresented: Bool

    @State private var query = ""
    @State private var results: [CommandPaletteResult] = []
    @State private var engine: CommandPaletteSearchEngine?

    public init(
        navigator: MacSvnAppNavigator,
        workspaceController: MacSvnWorkspaceController,
        session: MacSvnAppSession,
        isPresented: Binding<Bool>
    ) {
        self.navigator = navigator
        self.workspaceController = workspaceController
        self.session = session
        _isPresented = isPresented
    }

    public var body: some View {
        VStack(spacing: 0) {
            TextField("搜索命令、文件、日志…", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(16)
                .onChange(of: query) { _, _ in
                    results = engine?.search(query) ?? []
                }

            List(results, id: \.title) { result in
                Button {
                    select(result)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title)
                        if let subtitle = result.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 520, height: 360)
        .task { await rebuildEngine() }
    }

    private func rebuildEngine() async {
        let actions = [
            CommandPaletteAction(id: .commit, title: "提交更改", keywords: ["commit", "ci", "提交"]),
            CommandPaletteAction(id: .update, title: "更新工作副本", keywords: ["update", "更新"]),
            CommandPaletteAction(id: .switchBranch, title: "切换分支", keywords: ["branch", "switch", "分支"]),
            CommandPaletteAction(id: .openWorkingCopy, title: "打开工作副本", keywords: ["workspace", "wc", "工作副本"])
        ]

        var files: [CommandPaletteFileItem] = []
        var logs: [LogEntry] = []
        if let record = workspaceController.selectedRecord, record.isValid {
            let wc = URL(fileURLWithPath: record.localPath)
            if let statuses = try? await session.svnService.status(wc: wc) {
                files = statuses.map { CommandPaletteFileItem(path: $0.path) }
            }
            let settings = await session.settingsStore.settings()
            let from = Revision(max(1, (record.revision?.value ?? 1) - settings.logBatchSize))
            logs = (try? await session.svnService.log(
                wc: wc,
                target: "",
                from: from,
                batch: settings.logBatchSize,
                verbose: false
            )) ?? []
        }

        engine = CommandPaletteSearchEngine(actions: actions, files: files, logs: logs)
        results = engine?.search(query) ?? []
    }

    private func select(_ result: CommandPaletteResult) {
        switch result.kind {
        case .action(let id):
            switch id {
            case .commit:
                navigator.selectedRoute = .commit
            case .update:
                navigator.selectedRoute = .changes
            case .switchBranch:
                navigator.selectedRoute = .branches
            case .openWorkingCopy:
                navigator.selectedRoute = .workspace
            }
        case .file:
            navigator.selectedRoute = .changes
        case .log:
            navigator.selectedRoute = .log
        case .aiChat:
            navigator.selectedRoute = .aiAssistant
        }
        isPresented = false
    }
}
