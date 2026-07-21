import SwiftUI
import MacSvnCore
import AppKit

/// 分支与标签：列表、创建、切换。
public struct MacSvnBranchesView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
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
    @State private var selectedReferenceURL: String?
    @State private var referenceFilter: ReferenceFilter = .all
    @State private var showCreateSheet = false

    private enum ReferenceFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case branch = "分支"
        case tag = "标签"

        var id: String { rawValue }
    }

    private enum CopySourceMode: String, CaseIterable, Identifiable {
        case head = "HEAD"
        case revision = "指定 revision"
        case workingCopy = "当前工作副本"
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
            branchToolbar
            branchFilterBar
            if workspaceController.selectedRecord == nil {
                ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
            } else {
                branchWorkspace
            }
        }
        .task {
            await reload()
            consumePendingBranchCreation()
        }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await reload() }
        }
        .onChange(of: createMessage) { _, message in
            if message != createMessageTemplate {
                createMessageAutomaticallyFilled = false
            }
        }
        .onChange(of: referenceFilter) { _, _ in
            if let selectedReferenceURL,
               !filteredReferences.contains(where: { $0.url == selectedReferenceURL }) {
                self.selectedReferenceURL = filteredReferences.first?.url
            }
        }
        .onChange(of: navigator.pendingBranchCreation) { _, isPending in
            if isPending {
                consumePendingBranchCreation()
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            createSheet
                .macSvnDismissibleSheet()
        }
        .confirmationDialog(
            "存在未提交变更，确认仍要切换分支？",
            isPresented: $confirmLocalChanges,
            titleVisibility: .visible
        ) {
            Button("仍要切换", role: .destructive) {
                Task { await confirmSwitchWithLocalChanges() }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var branchToolbar: some View {
        HStack(spacing: 8) {
            Label("分支与标签", systemImage: "arrow.triangle.branch")
                .font(.headline)
            if let browserVM {
                Text("\(browserVM.branchList.branches.count) / \(browserVM.branchList.tags.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(browserVM == nil)
            .help("刷新分支与标签")
            .accessibilityLabel("刷新分支与标签")
            .accessibilityIdentifier("macSvn.branches.refresh")
            .keyboardShortcut("r", modifiers: .command)
            Button {
                showCreateSheet = true
            } label: {
                Label("创建分支/标签", systemImage: "plus")
            }
            .disabled(workspaceController.selectedRecord?.isValid != true || copyVM?.state == .copying)
        }
        .padding(.horizontal, 12)
        .frame(height: MacSvnCoreModeMetrics.toolbarHeight)
    }

    private var branchFilterBar: some View {
        HStack(spacing: 8) {
            Picker("引用筛选", selection: $referenceFilter) {
                ForEach(ReferenceFilter.allCases) { filter in
                    Text(LocalizedStringKey(filter.rawValue)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            Spacer(minLength: 8)
            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(minHeight: 36)
    }

    private var branchWorkspace: some View {
        HStack(spacing: 0) {
            branchList
                .frame(
                    minWidth: MacSvnCoreModeMetrics.masterMinimumWidth,
                    idealWidth: MacSvnCoreModeMetrics.masterIdealWidth,
                    maxWidth: MacSvnCoreModeMetrics.masterMaximumWidth
                )
            Divider()
            branchInspector
                .frame(minWidth: MacSvnCoreModeMetrics.inspectorMinimumWidth)
        }
    }

    private var branchList: some View {
        List(selection: $selectedReferenceURL) {
            ForEach(filteredReferences, id: \.url) { reference in
                branchReferenceRow(reference)
                    .tag(reference.url)
            }
        }
        .overlay {
            if let browserVM {
                switch browserVM.state {
                case .idle, .loading:
                    ProgressView("加载分支与标签…")
                case .loaded where filteredReferences.isEmpty:
                    ContentUnavailableView("没有匹配的引用", systemImage: "arrow.triangle.branch")
                case .error(let message):
                    ContentUnavailableView(
                        "加载分支与标签失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(
                            LocalizedStringKey(MacSvnCoreModeErrorPresentation.message(message))
                        )
                    )
                    .help(message)
                case .loaded:
                    EmptyView()
                }
            }
        }
    }

    private func branchReferenceRow(_ reference: BranchReference) -> some View {
        HStack(spacing: 8) {
            Image(systemName: referenceKindSystemImage(reference.kind))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(reference.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(reference.url)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(reference.url)
            }
            Spacer(minLength: 8)
            if let revision = reference.revision {
                Text("r\(revision.value)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var branchInspector: some View {
        if let reference = selectedReference {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Label(
                            LocalizedStringKey(referenceKindLabel(reference.kind)),
                            systemImage: referenceKindSystemImage(reference.kind)
                        )
                        .font(.headline)
                        Spacer()
                        if let revision = reference.revision {
                            Text("r\(revision.value)")
                                .font(.headline.monospacedDigit())
                        }
                    }
                    Text(reference.name)
                        .font(.title2.weight(.semibold))
                    Text(reference.url)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(reference.url)
                    Label(referenceRelationLabel(reference), systemImage: referenceRelationSystemImage(reference))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let author = reference.author {
                        LabeledContent("作者", value: author)
                    }
                    if let date = reference.date {
                        LabeledContent("最后变更") {
                            Text(date, format: .dateTime.year().month().day().hour().minute())
                        }
                    }
                    Divider()
                    TextField("目标 revision（可选）", text: $switchRevisionText)
                        .textFieldStyle(.roundedBorder)
                        .help("留空切换到目标分支 HEAD")
                    HStack(spacing: 8) {
                        Button {
                            Task { await switchTo(reference.url) }
                        } label: {
                            Label("切换到此引用", systemImage: "arrow.triangle.swap")
                        }
                        .disabled(
                            workspaceController.selectedRecord?.isValid != true
                                || switchVM?.state == .switching
                        )
                        Button {
                            navigator.openMerge(sourceURL: reference.url)
                        } label: {
                            Label("在 Merge 向导中使用", systemImage: "arrow.triangle.merge")
                        }
                        referenceActionsMenu(reference)
                    }
                    mergeInfoSection
                    if case .confirmationRequired(let paths) = switchVM?.state {
                        Label(
                            "存在未提交变更（\(paths.count)），切换前需要确认",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        } else {
            ContentUnavailableView(
                "选择一个分支或标签",
                systemImage: "arrow.triangle.branch",
                description: Text("查看引用详情并执行切换或合并")
            )
        }
    }

    @ViewBuilder
    private var mergeInfoSection: some View {
        Divider()
        Text("svn:mergeinfo（当前工作副本）")
            .font(.headline)
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

    private func referenceActionsMenu(_ reference: BranchReference) -> some View {
        Menu {
            Button("查看日志", systemImage: "clock.arrow.circlepath") {
                openReferenceLog(reference)
            }
            .disabled(reference.revision == nil)
            Button("检出…", systemImage: "square.and.arrow.down") {
                checkoutReference(reference)
            }
            Divider()
            Button("复制 URL", systemImage: "doc.on.doc") {
                copyReferenceURL(reference)
            }
        } label: {
            Label("更多引用操作", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("更多引用操作")
        .accessibilityLabel("更多引用操作")
    }

    private var createSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("创建分支或标签", systemImage: "plus")
                .font(.title2.weight(.semibold))
            Picker("类型", selection: $createKind) {
                Text("分支").tag(BranchReferenceKind.branch)
                Text("标签").tag(BranchReferenceKind.tag)
            }
            .pickerStyle(.segmented)
            Picker("来源", selection: $createSourceMode) {
                ForEach(CopySourceMode.allCases) { mode in
                    Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                }
            }
            if createSourceMode == .revision {
                TextField("来源 revision", text: $createRevisionText)
                    .textFieldStyle(.roundedBorder)
            } else if createSourceMode == .workingCopy,
                      let path = workspaceController.selectedRecord?.localPath {
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(path)
            }
            TextField("名称", text: $newName)
                .textFieldStyle(.roundedBorder)
            TextField("提交说明", text: $createMessage)
                .textFieldStyle(.roundedBorder)
            if case .error(let message) = copyVM?.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                if copyVM?.state == .copying {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("取消") { showCreateSheet = false }
                Button("创建") { Task { await createBranch() } }
                    .disabled(
                        newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || copyVM?.state == .copying
                    )
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
    }

    private func consumePendingBranchCreation() {
        guard navigator.consumePendingBranchCreation() else { return }
        showCreateSheet = true
    }

    private var allReferences: [BranchReference] {
        guard let browserVM else { return [] }
        return [browserVM.branchList.trunk].compactMap { $0 }
            + browserVM.branchList.branches
            + browserVM.branchList.tags
    }

    private var filteredReferences: [BranchReference] {
        guard let browserVM else { return [] }
        switch referenceFilter {
        case .all:
            return allReferences
        case .branch:
            return browserVM.branchList.branches
        case .tag:
            return browserVM.branchList.tags
        }
    }

    private var selectedReference: BranchReference? {
        guard let selectedReferenceURL else { return nil }
        return allReferences.first(where: { $0.url == selectedReferenceURL })
    }

    private func referenceKindLabel(_ kind: BranchReferenceKind) -> String {
        switch kind {
        case .trunk: return "主干"
        case .branch: return "分支"
        case .tag: return "标签"
        }
    }

    private func referenceKindSystemImage(_ kind: BranchReferenceKind) -> String {
        switch kind {
        case .trunk: return "arrow.up"
        case .branch: return "arrow.triangle.branch"
        case .tag: return "tag"
        }
    }

    private func referenceRelationLabel(_ reference: BranchReference) -> LocalizedStringKey {
        guard let currentURL = workspaceController.selectedRecord?.repoURL else {
            return "没有当前工作副本"
        }
        return normalizedRepositoryURL(currentURL) == normalizedRepositoryURL(reference.url)
            ? "当前工作副本位于此引用"
            : "当前工作副本位于其他引用"
    }

    private func referenceRelationSystemImage(_ reference: BranchReference) -> String {
        guard let currentURL = workspaceController.selectedRecord?.repoURL else {
            return "questionmark.circle"
        }
        return normalizedRepositoryURL(currentURL) == normalizedRepositoryURL(reference.url)
            ? "checkmark.circle.fill"
            : "arrow.left.arrow.right"
    }

    private func normalizedRepositoryURL(_ url: String) -> String {
        var normalized = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    private func openReferenceLog(_ reference: BranchReference) {
        guard let revision = reference.revision else { return }
        navigator.pendingRevisionGraphLog = PendingRevisionGraphLogIntent(
            url: reference.url,
            revision: revision
        )
        navigator.selectMode(.history)
    }

    private func checkoutReference(_ reference: BranchReference) {
        navigator.pendingTransferIntent = PendingTransferIntent(
            command: .checkout,
            path: nil,
            url: reference.url,
            revision: reference.revision,
            message: nil
        )
        navigator.selectMode(.browser)
    }

    private func copyReferenceURL(_ reference: BranchReference) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reference.url, forType: .string)
        statusText = "已复制 \(reference.name) URL"
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
            selectedReferenceURL = nil
            return
        }
        let previousSelection = selectedReferenceURL
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
            statusText = "加载失败：\(MacSvnCoreModeErrorPresentation.message(message))"
        } else {
            if let previousSelection,
               filteredReferences.contains(where: { $0.url == previousSelection }) {
                selectedReferenceURL = previousSelection
            } else {
                selectedReferenceURL = filteredReferences.first?.url
            }
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
            showCreateSheet = false
            newName = ""
            createRevisionText = ""
            createMessageAutomaticallyFilled = true
            createMessageTemplate = nil
            await reload()
            statusText = "创建成功 r\(revision.value)"
        case .error(let message):
            statusText = "创建失败：\(MacSvnCoreModeErrorPresentation.message(message))"
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
        await applySwitchState(switchVM)
    }

    private func confirmSwitchWithLocalChanges() async {
        guard let switchVM else { return }
        await switchVM.confirmSwitchWithLocalChanges()
        await applySwitchState(switchVM)
    }

    private func applySwitchState(_ switchVM: BranchSwitchViewModel) async {
        switch switchVM.state {
        case .completed:
            confirmLocalChanges = false
            await workspaceController.reload()
            await reload()
            statusText = "切换完成"
        case .confirmationRequired:
            confirmLocalChanges = true
        case .error(let message):
            confirmLocalChanges = false
            statusText = "切换失败：\(MacSvnCoreModeErrorPresentation.message(message))"
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
