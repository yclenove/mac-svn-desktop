import SwiftUI
import MacSvnCore

/// 分支与标签：列表、创建、切换。
public struct MacSvnBranchesView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let session: MacSvnAppSession

    @State private var browserVM: BranchBrowserViewModel?
    @State private var copyVM: BranchCopyViewModel?
    @State private var switchVM: BranchSwitchViewModel?
    @State private var mergeInfoVM: MergeInfoViewModel?
    @State private var newName = ""
    @State private var createMessage = "create branch"
    @State private var createMessageTemplate: String?
    @State private var createMessageAutomaticallyFilled = true
    @State private var projectProperties = ProjectPropertyPolicy(properties: [])
    @State private var createKind: BranchReferenceKind = .branch
    @State private var createSourceMode: CopySourceMode = .head
    @State private var createRevisionText = ""
    @State private var switchRevisionText = ""
    @State private var statusText: LocalizedStringKey?
    @State private var confirmLocalChanges = false

    private enum CopySourceMode: String, CaseIterable, Identifiable {
        case head = "HEAD"
        case revision = "指定 revision"
        case workingCopy = "当前工作副本"
        var id: String { rawValue }
    }

    public init(workspaceController: MacSvnWorkspaceController, session: MacSvnAppSession) {
        self.workspaceController = workspaceController
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("分支与标签")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Button("刷新") { Task { await reload() } }
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
                    List {
                        if let trunk = browserVM?.branchList.trunk {
                            Section("Trunk") {
                                branchRow(trunk)
                            }
                        }
                        Section("Branches") {
                            ForEach(browserVM?.branchList.branches ?? [], id: \.url) { branch in
                                branchRow(branch)
                            }
                        }
                        Section("Tags") {
                            ForEach(browserVM?.branchList.tags ?? [], id: \.url) { tag in
                                branchRow(tag)
                            }
                        }
                    }
                    .frame(minWidth: 320)

                    Form {
                        Section("创建") {
                            Picker("类型", selection: $createKind) {
                                Text("分支").tag(BranchReferenceKind.branch)
                                Text("标签").tag(BranchReferenceKind.tag)
                            }
                            Picker("来源", selection: $createSourceMode) {
                                ForEach(CopySourceMode.allCases) { mode in
                                    Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                                }
                            }
                            if createSourceMode == .revision {
                                TextField("来源 revision", text: $createRevisionText)
                            } else if createSourceMode == .workingCopy,
                                      let path = workspaceController.selectedRecord?.localPath {
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            TextField("名称", text: $newName)
                            TextField("提交说明", text: $createMessage)
                            Button("创建") { Task { await createBranch() } }
                                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Section("切换选项") {
                            TextField("目标 revision（可选）", text: $switchRevisionText)
                                .help("留空切换到目标分支 HEAD")
                        }
                        Section("svn:mergeinfo（当前 WC）") {
                            if let mergeInfoVM {
                                switch mergeInfoVM.state {
                                case .loading:
                                    ProgressView("加载 mergeinfo…")
                                case .error(let message):
                                    Text(message).foregroundStyle(.red)
                                case .loaded where mergeInfoVM.entries.isEmpty:
                                    Text("无 mergeinfo")
                                        .foregroundStyle(.secondary)
                                case .loaded, .idle:
                                    Text("已合并 revision 合计 \(mergeInfoVM.totalMergedRevisionCount)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ForEach(mergeInfoVM.entries, id: \.sourcePath) { entry in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.sourcePath)
                                                .font(.caption.weight(.semibold))
                                            Text(entry.ranges.map(rangeLabel).joined(separator: ", "))
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Button("刷新 mergeinfo") {
                                    Task { await mergeInfoVM.load() }
                                }
                            } else {
                                Text("未加载")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if case .confirmationRequired(let paths) = switchVM?.state {
                            Section("切换确认") {
                                Text("存在未提交变更（\(paths.count)）：继续切换可能混淆变更归属。")
                                    .foregroundStyle(.orange)
                                Button("仍要切换") {
                                    Task { await switchVM?.confirmSwitchWithLocalChanges() }
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .frame(minWidth: 300)
                }
            }
        }
        .task { await reload() }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await reload() }
        }
        .onChange(of: createMessage) { _, message in
            if message != createMessageTemplate {
                createMessageAutomaticallyFilled = false
            }
        }
        .confirmationDialog(
            "存在未提交变更，确认仍要切换分支？",
            isPresented: $confirmLocalChanges,
            titleVisibility: .visible
        ) {
            Button("仍要切换", role: .destructive) {
                Task { await switchVM?.confirmSwitchWithLocalChanges() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func branchRow(_ ref: BranchReference) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.name)
                    .font(.headline)
                Text(ref.url)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("切换到此") {
                Task { await switchTo(ref.url) }
            }
            .disabled(workspaceController.selectedRecord?.isValid != true)
        }
    }

    private func rangeLabel(_ range: MergeInfoRevisionRange) -> String {
        if range.start == range.end {
            return "r\(range.start.value)"
        }
        return "r\(range.start.value)-\(range.end.value)"
    }

    private func reload() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            browserVM = nil
            mergeInfoVM = nil
            return
        }
        let settings = await session.settingsStore.settings()
        let browser = BranchBrowserViewModel(provider: session.branchListService)
        browserVM = browser
        copyVM = BranchCopyViewModel(copyProvider: session.svnService)
        switchVM = BranchSwitchViewModel(provider: session.svnService)
        let wc = URL(fileURLWithPath: record.localPath)
        projectProperties = (try? await MacSvnProjectPropertyLoader.load(
            svnService: session.svnService,
            workingCopy: wc,
            relativePaths: ["."]
        )) ?? ProjectPropertyPolicy(properties: [])
        applyCreateMessageTemplate()
        let mergeInfo = MergeInfoViewModel(workingCopy: wc, target: ".", provider: session.svnService)
        mergeInfoVM = mergeInfo

        // repositoryRoot：优先用 info 的 repositoryRoot，否则从 WC URL 推断
        let root: String
        if let info = try? await session.svnService.info(
            wc: wc,
            target: "."
        ), let repositoryRoot = info.repositoryRoot, !repositoryRoot.isEmpty {
            root = repositoryRoot
        } else {
            root = record.repoURL
        }

        await browser.load(repositoryRoot: root, layout: settings.branchLayout)
        await mergeInfo.load()
        if case .error(let message) = browser.state {
            statusText = "加载失败：\(message)"
        } else {
            let mergeSuffix: String
            if case .loaded = mergeInfo.state {
                mergeSuffix = "；mergeinfo \(mergeInfo.totalMergedRevisionCount) rev"
            } else if case .error = mergeInfo.state {
                mergeSuffix = "；mergeinfo 加载失败"
            } else {
                mergeSuffix = ""
            }
            statusText = "分支 \(browser.branchList.branches.count) / 标签 \(browser.branchList.tags.count)\(mergeSuffix)"
        }
    }

    private func createBranch() async {
        guard let record = workspaceController.selectedRecord,
              let copyVM,
              let info = try? await session.svnService.info(
                wc: URL(fileURLWithPath: record.localPath),
                target: "."
              )
        else { return }

        let settings = await session.settingsStore.settings()
        let root = info.repositoryRoot ?? record.repoURL
        let source: BranchCopySource
        switch createSourceMode {
        case .head:
            source = .head(repositoryURL: info.url)
        case .revision:
            guard let value = Int(createRevisionText.trimmingCharacters(in: .whitespacesAndNewlines)), value >= 0 else {
                statusText = "创建失败：revision 必须是非负整数"
                return
            }
            source = .revision(repositoryURL: info.url, revision: Revision(value))
        case .workingCopy:
            source = .workingCopy(URL(fileURLWithPath: record.localPath))
        }
        await copyVM.create(
            kind: createKind,
            source: source,
            repositoryRoot: root,
            name: newName,
            layout: settings.branchLayout,
            message: createMessage
        )
        switch copyVM.state {
        case .completed(let revision):
            statusText = "创建成功 r\(revision.value)"
            newName = ""
            createRevisionText = ""
            await reload()
        case .error(let message):
            statusText = "创建失败：\(message)"
        default:
            break
        }
    }

    private func switchTo(_ url: String) async {
        guard let record = workspaceController.selectedRecord, let switchVM else { return }
        let trimmedRevision = switchRevisionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let revision: Revision?
        if trimmedRevision.isEmpty {
            revision = nil
        } else if let value = Int(trimmedRevision), value >= 0 {
            revision = Revision(value)
        } else {
            statusText = "切换失败：revision 必须是非负整数"
            return
        }
        await switchVM.switchTo(
            wc: URL(fileURLWithPath: record.localPath),
            url: url,
            revision: revision
        )
        switch switchVM.state {
        case .completed:
            statusText = "切换完成"
            await workspaceController.reload()
        case .confirmationRequired:
            confirmLocalChanges = true
        case .error(let message):
            statusText = "切换失败：\(message)"
        default:
            break
        }
    }

    private func applyCreateMessageTemplate() {
        guard createMessageAutomaticallyFilled else { return }
        let template = projectProperties.initialMessage(for: .branch) ?? "create branch"
        createMessageTemplate = template
        createMessage = template
    }
}
