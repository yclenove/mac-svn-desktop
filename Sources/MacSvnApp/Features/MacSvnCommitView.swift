import SwiftUI
import MacSvnCore

/// 提交页：接 CommitViewModel + 提交说明历史 + Commit Guard 警告。
public struct MacSvnCommitView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    @ObservedObject private var session: MacSvnAppSession
    private let embedded: Bool

    @State private var viewModel: CommitViewModel?
    @State private var statusText: LocalizedStringKey?
    @State private var bugtraqIssueInput = ""
    @State private var completionCandidates: [String] = []
    @State private var completionGeneration = 0

    public init(
        workspaceController: MacSvnWorkspaceController,
        session: MacSvnAppSession,
        navigator: MacSvnAppNavigator,
        embedded: Bool = false
    ) {
        self.workspaceController = workspaceController
        self.session = session
        self.navigator = navigator
        self.embedded = embedded
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("提交")
                    .font(embedded ? .headline : .largeTitle.weight(.semibold))
                Spacer()
                Button("AI 生成说明") {
                    Task { await runAICommitMessage() }
                }
                .disabled(viewModel == nil)
                Button("AI 预检") {
                    Task { await runAIReview() }
                }
                .disabled(viewModel == nil)
                Button("刷新候选") {
                    Task { await reloadCandidates() }
                }
                Button("提交") {
                    Task { await commit(skipWarnings: false) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel?.canCommit != true)
            }
            .padding(embedded ? 12 : 24)

            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, embedded ? 12 : 24)
            }

            content
        }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await reloadCandidates() }
        }
        .onChange(of: navigator.pendingCommitMessage) { _, newValue in
            guard newValue != nil else { return }
            applyPendingCommitMessage()
        }
        .onChange(of: viewModel?.selectedPaths) { _, _ in
            guard let viewModel else { return }
            Task { await viewModel.refreshProjectProperties() }
        }
        .onChange(of: session.settingsSnapshot.dialogs) { oldDialogs, dialogs in
            Task { await applyDialogSettings(old: oldDialogs, new: dialogs) }
        }
        .task {
            await reloadCandidates()
            applyPendingCommitMessage()
        }
    }

    @ViewBuilder
    private var content: some View {
        if workspaceController.selectedRecord == nil {
            ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
        } else if let viewModel {
            // 嵌入变更工作区禁止 HSplitView（AttributeGraph 风险）；独立页可用 Split
            if embedded {
                HStack(alignment: .top, spacing: 0) {
                    candidateList(viewModel)
                        .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)
                    Divider()
                    messagePanel(viewModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                HSplitView {
                    candidateList(viewModel)
                        .frame(minWidth: 280)
                    messagePanel(viewModel)
                        .frame(minWidth: 360)
                }
            }
        } else {
            ProgressView("加载变更…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func candidateList(_ viewModel: CommitViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if !viewModel.availableChangelists.isEmpty {
                    Picker("范围", selection: Binding<String?>(
                        get: { viewModel.selectedChangelist },
                        set: { viewModel.selectChangelist($0) }
                    )) {
                        Text("全部可提交").tag(nil as String?)
                        ForEach(viewModel.availableChangelists, id: \.self) { name in
                            Text(name).tag(Optional(name))
                        }
                    }
                    .frame(maxWidth: 220)
                    .disabled(viewModel.state == .committing || viewModel.state == .reverting)
                }
                Button("Diff") {
                    diffSelected(viewModel)
                }
                .disabled(viewModel.orderedSelectedPaths.count != 1)

                Button("还原") {
                    Task { await revertSelected(viewModel) }
                }
                .disabled(viewModel.orderedSelectedPaths.isEmpty || viewModel.state == .committing)

                Spacer()
                Text("已选 \(viewModel.orderedSelectedPaths.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List {
                ForEach(viewModel.candidateStatuses, id: \.path) { status in
                    Toggle(isOn: Binding(
                        get: { viewModel.selectedPaths.contains(status.path) },
                        set: { viewModel.setSelected($0, for: status.path) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.path)
                            HStack(spacing: 6) {
                                Text(status.itemStatus.rawValue)
                                if status.itemStatus == .unversioned {
                                    Text("提交前将 add")
                                }
                                if let changelist = status.changelist {
                                    Text(changelist)
                                        .foregroundStyle(
                                            ChangelistPolicy.isIgnoredOnCommit(changelist) ? .orange : .secondary
                                        )
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(
                        status.itemStatus == .conflicted
                            || status.isTreeConflict
                            || viewModel.state == .committing
                            || viewModel.state == .reverting
                    )
                    .contextMenu {
                        Button("Diff") {
                            _ = navigator.perform(command: .diff, paths: [status.path])
                        }
                        Button("还原") {
                            Task {
                                await viewModel.revertSelected(paths: [status.path])
                                if case .reverted = viewModel.state {
                                    await reloadCandidates()
                                }
                            }
                        }
                        .disabled(status.itemStatus == .unversioned)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messagePanel(_ viewModel: CommitViewModel) -> some View {
        let dialogs = session.settingsSnapshot.dialogs
        VStack(alignment: .leading, spacing: 12) {
            Text("提交说明")
                .font(.headline)
            BugtraqIssueTextEditor(text: Binding(
                get: { viewModel.message },
                set: { viewModel.message = $0 }
            ), regexPatterns: viewModel.projectProperties.bugtraq.regexPatterns,
               spellcheckLanguage: ProjectSpellcheckLanguage.resolve(viewModel.projectProperties.projectLanguage),
               completionCandidates: completionCandidates,
               isAutoCompletionEnabled: dialogs.enableCommitAutoCompletion,
               fontName: dialogs.logFontName,
               fontSize: dialogs.logFontSize)
            .frame(minHeight: embedded ? 80 : 160)

            Toggle("Keep locks（提交后保留锁）", isOn: Binding(
                get: { viewModel.keepLocks },
                set: { viewModel.keepLocks = $0 }
            ))
            .font(.callout)

            projectPropertyPanel(viewModel)

            if !viewModel.recentMessages.isEmpty {
                Text("最近说明")
                    .font(.subheadline.weight(.semibold))
                ForEach(viewModel.recentMessages, id: \.self) { recent in
                    Button(recent) {
                        viewModel.reuseRecentMessage(recent)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(2)
                }
            }

            if case .guardWarnings(let issues) = viewModel.state {
                VStack(alignment: .leading, spacing: 6) {
                    Text("提交守护警告")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Text("• \(issue.message)")
                            .font(.caption)
                    }
                    Button("忽略警告并提交") {
                        Task { await commit(skipWarnings: true) }
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if case .committed(let revision) = viewModel.state {
                Text("已提交 r\(revision.value)")
                    .foregroundStyle(.green)
            }

            if case .reverted = viewModel.state {
                Text("已还原选中项")
                    .foregroundStyle(.secondary)
            }

            if case .error(let message) = viewModel.state {
                Text(message)
                    .foregroundStyle(.red)
            }

            aiStatusSection(viewModel)

            Spacer(minLength: 0)
        }
        .padding(embedded ? 8 : 16)
    }

    @ViewBuilder
    private func projectPropertyPanel(_ viewModel: CommitViewModel) -> some View {
        let properties = viewModel.projectProperties
        if properties.commit.minimumMessageLength != nil
            || properties.commit.widthMarker != nil
            || properties.projectLanguage != nil
            || properties.bugtraq.usesInputMode
            || !viewModel.issueReferences.isEmpty
            || viewModel.projectPropertyLoadError != nil
            || !properties.diagnostics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let minimum = properties.commit.minimumMessageLength {
                    Text("最少 \(minimum) 个字符")
                        .font(.caption)
                        .foregroundStyle(CommitMessagePolicy.validationError(
                            for: viewModel.message,
                            properties: properties
                        ) == nil ? Color.secondary : Color.red)
                }
                if !viewModel.overlongMessageLineNumbers.isEmpty {
                    Text("超过宽度标记的行：\(viewModel.overlongMessageLineNumbers.map(String.init).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let language = properties.projectLanguage {
                    Text("项目拼写语言：\(ProjectSpellcheckLanguage.resolve(language) ?? language)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let loadError = viewModel.projectPropertyLoadError {
                    Text("项目属性读取失败，已阻止提交：\(loadError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if properties.bugtraq.usesInputMode {
                    HStack(spacing: 8) {
                        TextField("Issue", text: $bugtraqIssueInput)
                            .textFieldStyle(.roundedBorder)
                        Button(properties.bugtraq.appendMessage ? "追加" : "插入") {
                            if viewModel.applyBugtraqIssueInput(bugtraqIssueInput) {
                                bugtraqIssueInput = ""
                            }
                        }
                        .disabled(bugtraqIssueInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if !viewModel.issueReferences.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(viewModel.issueReferences) { issue in
                            if let url = issue.url, let link = URL(string: url) {
                                Link(issue.identifier, destination: link)
                                    .font(.caption)
                            } else {
                                Text(issue.identifier)
                                    .font(.caption)
                            }
                        }
                    }
                }
                ForEach(Array(properties.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                    Text(projectPropertyDiagnosticText(diagnostic))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private func aiStatusSection(_ viewModel: CommitViewModel) -> some View {
        if case .generating = viewModel.aiCommitMessageState {
            ProgressView("AI 正在生成提交说明…")
        }
        if case .error(let message) = viewModel.aiCommitMessageState {
            Text("AI 说明失败：\(message)").foregroundStyle(.red).font(.caption)
        }
        if case .reviewing = viewModel.aiPreCommitReviewState {
            ProgressView("AI 预检中…")
        }
        if case .reviewed(let result) = viewModel.aiPreCommitReviewState {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI 预检：\(result.summary)").font(.headline)
                ForEach(Array(result.findings.prefix(8).enumerated()), id: \.offset) { _, finding in
                    Text("• [\(finding.severity.rawValue)] \(finding.message)")
                        .font(.caption)
                }
            }
        }
        if case .error(let message) = viewModel.aiPreCommitReviewState {
            Text("AI 预检失败：\(message)").foregroundStyle(.red).font(.caption)
        }
    }

    private func applyPendingCommitMessage() {
        guard let viewModel else { return }
        guard let message = navigator.consumePendingCommitMessage(), !message.isEmpty else { return }
        viewModel.message = message
        statusText = "已填入预置提交说明"
    }

    private func reloadCandidates() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            viewModel = nil
            completionCandidates = []
            return
        }
        let wc = URL(fileURLWithPath: record.localPath)
        do {
            let settings = await session.settingsStore.settings()
            let rawStatuses: [FileStatus]
            if settings.dialogs.recurseIntoUnversionedFolders {
                rawStatuses = try await session.svnService.statusIncludingIgnored(wc: wc)
            } else {
                rawStatuses = try await session.svnService.status(wc: wc)
            }
            let statuses = try await UnversionedTreeExpander.expandAsync(
                statuses: rawStatuses,
                workingCopy: wc,
                recurse: settings.dialogs.recurseIntoUnversionedFolders
            ).filter { $0.itemStatus != .ignored }
            let candidates = CommitSelectionPolicy.candidates(from: statuses)
            let projectProperties = try await MacSvnProjectPropertyLoader.load(
                svnService: session.svnService,
                workingCopy: wc,
                relativePaths: candidates.map(\.path)
            )
            let vm = CommitViewModel(
                workingCopy: wc,
                statuses: statuses,
                commitProvider: session.svnService,
                statusProvider: session.svnService,
                aiCommitMessageGenerator: session.aiCommitMessageGenerator,
                aiPreCommitReviewer: session.aiPreCommitReviewer,
                commitMessageHistoryProvider: session.commitMessageHistoryStore,
                projectPropertyLoader: { [svnService = session.svnService] paths in
                    try await MacSvnProjectPropertyLoader.load(
                        svnService: svnService,
                        workingCopy: wc,
                        relativePaths: paths
                    )
                },
                projectProperties: projectProperties,
                selectItemsAutomatically: settings.dialogs.selectCommitItemsAutomatically,
                useTrashWhenReverting: settings.dialogs.useTrashWhenReverting
            )
            viewModel = vm
            await vm.loadRecentMessages()
            await rebuildCompletionCandidates(for: vm, dialogs: settings.dialogs)
            statusText = "候选 \(vm.candidateStatuses.count) 项"
            applyPendingCommitMessage()
        } catch {
            statusText = "加载失败：\(error.localizedDescription)"
            viewModel = nil
        }
    }

    private func applyDialogSettings(old: DialogSettings, new: DialogSettings) async {
        viewModel?.updateSettings(
            selectItemsAutomatically: new.selectCommitItemsAutomatically,
            useTrashWhenReverting: new.useTrashWhenReverting
        )
        if old.recurseIntoUnversionedFolders != new.recurseIntoUnversionedFolders {
            let draft = viewModel?.message
            let selection = viewModel?.selectedPaths ?? []
            await reloadCandidates()
            if let draft, let viewModel {
                viewModel.message = draft
                viewModel.selectedPaths = selection.intersection(Set(viewModel.candidateStatuses.map(\.path)))
            }
        } else {
            await rebuildCompletionCandidates(dialogs: new)
        }
    }

    private func commit(skipWarnings: Bool) async {
        guard let viewModel else { return }
        await viewModel.commit(auth: nil, skipGuardWarnings: skipWarnings)
        if case .committed(let revision) = viewModel.state {
            if session.settingsSnapshot.dialogs.reopenCommitAfterSuccessWithRemainingItems,
               !CommitSelectionPolicy.candidates(from: viewModel.refreshedStatuses).isEmpty {
                await reloadCandidates()
                statusText = "提交成功 r\(revision.value)，仍有未提交项"
            } else {
                statusText = "提交成功 r\(revision.value)"
                await rebuildCompletionCandidates(for: viewModel)
            }
        }
    }

    private func rebuildCompletionCandidates(
        for targetViewModel: CommitViewModel? = nil,
        dialogs: DialogSettings? = nil
    ) async {
        completionGeneration += 1
        let generation = completionGeneration
        guard let targetViewModel = targetViewModel ?? viewModel else {
            completionCandidates = []
            return
        }
        let preferences = dialogs ?? session.settingsSnapshot.dialogs
        guard preferences.enableCommitAutoCompletion else {
            completionCandidates = []
            return
        }
        let paths = targetViewModel.candidateStatuses.map(\.path)
        let recentMessages = targetViewModel.recentMessages
        let timeout = TimeInterval(preferences.autoCompletionTimeoutSeconds)
        let candidates = await Task.detached(priority: .utility) {
            CommitMessageCompletionCandidates.build(
                paths: paths,
                recentMessages: recentMessages,
                timeout: timeout
            )
        }.value
        guard generation == completionGeneration else { return }
        completionCandidates = candidates
    }

    private func diffSelected(_ viewModel: CommitViewModel) {
        guard let path = viewModel.orderedSelectedPaths.first,
              viewModel.orderedSelectedPaths.count == 1 else { return }
        _ = navigator.perform(command: .diff, paths: [path])
    }

    private func revertSelected(_ viewModel: CommitViewModel) async {
        await viewModel.revertSelected()
        if case .reverted = viewModel.state {
            statusText = "已还原"
            await reloadCandidates()
        } else if case .error(let message) = viewModel.state {
            statusText = "还原失败：\(message)"
        }
    }

    private func runAICommitMessage() async {
        guard let viewModel else { return }
        let privacy = await session.currentAIPrivacy()
        await viewModel.generateAICommitMessage(privacySettings: privacy)
        if case .generated = viewModel.aiCommitMessageState {
            statusText = "AI 提交说明已填入"
        }
    }

    private func runAIReview() async {
        guard let viewModel else { return }
        let privacy = await session.currentAIPrivacy()
        await viewModel.runAIPreCommitReview(privacySettings: privacy)
        if case .reviewed = viewModel.aiPreCommitReviewState {
            statusText = "AI 预检完成"
        }
    }

    private func projectPropertyDiagnosticText(_ diagnostic: ProjectPropertyDiagnostic) -> String {
        switch diagnostic {
        case .invalidNonNegativeInteger(let name, let value):
            return "\(name) 需要非负整数：\(value)"
        case .invalidBoolean(let name, let value):
            return "\(name) 需要 true/false：\(value)"
        case .invalidBugtraqRegex(let value):
            return "bugtraq:logregex 无效：\(value)"
        case .invalidBugtraqRegexLineCount(let count):
            return "bugtraq:logregex 需要 1 或 2 行，当前 \(count) 行"
        case .bugtraqMessageMissingPlaceholder:
            return "bugtraq:message 缺少 %BUGID%"
        case .bugtraqRepositoryRootUnavailable:
            return "bugtraq:url 使用 ^/，但无法读取仓库根 URL"
        case .conflictingProjectProperty(let name):
            return "选中路径的 \(name) 配置不一致，已使用保守规则"
        }
    }
}
