import SwiftUI
import MacSvnCore

/// ⌘K 命令面板：动作 / 路由 / 文件 / 日志模糊搜索。
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
            TextField("搜索命令、页面、文件、日志…", text: $query)
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
        let actions: [CommandPaletteAction] = [
            CommandPaletteAction(id: .commit, title: "提交更改", keywords: ["commit", "ci", "提交"]),
            CommandPaletteAction(id: .update, title: "更新工作副本", keywords: ["update", "更新"]),
            CommandPaletteAction(id: .switchBranch, title: "切换分支", keywords: ["branch", "switch", "分支"]),
            CommandPaletteAction(id: .openWorkingCopy, title: "添加工作副本", keywords: ["workspace", "wc", "工作副本", "添加"]),
            CommandPaletteAction(id: .goChanges, title: "打开：变更工作区", keywords: ["changes", "变更", "status"]),
            CommandPaletteAction(id: .goHistory, title: "打开：历史", keywords: ["log", "历史", "日志"]),
            CommandPaletteAction(id: .goBrowser, title: "打开：仓库浏览器", keywords: ["browser", "浏览", "repo"]),
            CommandPaletteAction(id: .goBranches, title: "打开：分支与标签", keywords: ["branches", "分支", "tag"]),
            CommandPaletteAction(id: .goConflicts, title: "打开：冲突合并", keywords: ["merge", "冲突", "conflict"]),
            CommandPaletteAction(id: .goBlame, title: "打开：Blame", keywords: ["blame", "追溯"]),
            CommandPaletteAction(id: .goProperties, title: "打开：属性", keywords: ["properties", "属性", "prop"]),
            CommandPaletteAction(id: .goLocks, title: "打开：锁定", keywords: ["lock", "锁定"]),
            CommandPaletteAction(id: .goShelve, title: "打开：本地搁置", keywords: ["shelve", "搁置"]),
            CommandPaletteAction(id: .goGitMigration, title: "打开：Git 迁移", keywords: ["git", "迁移"]),
            CommandPaletteAction(id: .goTeamActivity, title: "打开：团队动态", keywords: ["team", "团队", "heatmap"]),
            CommandPaletteAction(id: .goAIAssistant, title: "打开：AI 助手", keywords: ["ai", "助手", "chat"]),
            CommandPaletteAction(id: .goReleaseNotes, title: "打开：Release Notes", keywords: ["release", "notes", "发布"]),
            CommandPaletteAction(id: .goSettings, title: "打开：设置", keywords: ["settings", "设置", "prefs"]),
            CommandPaletteAction(id: .goDiff, title: "打开：差异（变更工作区）", keywords: ["diff", "差异"])
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
                navigator.selectRoute(.commit)
            case .update, .goChanges, .goDiff:
                navigator.selectMode(.changes)
            case .switchBranch, .goBranches:
                navigator.selectMode(.branches)
            case .openWorkingCopy:
                workspaceController.presentAddPanel()
            case .goHistory:
                navigator.selectMode(.history)
            case .goBrowser:
                navigator.selectMode(.browser)
            case .goConflicts:
                navigator.selectMode(.conflicts)
            case .goBlame:
                navigator.selectMode(.blame)
            case .goProperties:
                navigator.selectMode(.properties)
            case .goLocks:
                navigator.selectMode(.locks)
            case .goShelve:
                navigator.selectMode(.shelve)
            case .goGitMigration:
                navigator.selectMode(.gitMigration)
            case .goTeamActivity:
                navigator.selectMode(.teamActivity)
            case .goAIAssistant:
                navigator.selectMode(.aiAssistant)
            case .goReleaseNotes:
                navigator.selectMode(.releaseNotes)
            case .goSettings:
                navigator.selectMode(.settings)
            }
        case .file(let path):
            navigator.pendingDiffPath = path
            navigator.selectMode(.changes)
        case .log:
            navigator.selectMode(.history)
        case .aiChat(let query):
            navigator.handoffCommandPaletteQueryToAIChat(query)
        }
        isPresented = false
    }
}
