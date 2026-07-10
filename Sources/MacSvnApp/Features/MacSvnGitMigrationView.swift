import SwiftUI
import MacSvnCore
import AppKit

/// Git 迁移五步向导：源分析 → authors → 清理提示 → 执行 → 同步。
public struct MacSvnGitMigrationView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let session: MacSvnAppSession

    @State private var step: Step = .analyze
    @State private var sourceURL = ""
    @State private var mode: GitMigrationMode = .snapshot
    @State private var commitMessage = "Initial import from SVN"
    @State private var destinationPath = ""
    @State private var targetRemote = ""
    @State private var statusText: String?

    @State private var analysisVM: GitMigrationSourceAnalysisViewModel?
    @State private var authorVM: GitMigrationAuthorMappingViewModel?
    @State private var migrateVM: GitMigrationViewModel?
    @State private var syncVM: GitMigrationSyncViewModel?
    @State private var cleanupPlan: GitMigrationCleanupPlan?
    @State private var authorEmailDomain = "example.com"
    @State private var reconciliationVM: GitMigrationRevisionReconciliationViewModel?

    private enum Step: String, CaseIterable, Identifiable {
        case analyze = "1.源分析"
        case authors = "2.Authors"
        case cleanup = "3.清理"
        case execute = "4.执行"
        case sync = "5.同步"
        var id: String { rawValue }
    }

    public init(workspaceController: MacSvnWorkspaceController, session: MacSvnAppSession) {
        self.workspaceController = workspaceController
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Git 迁移")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Picker("", selection: $step) {
                    ForEach(Step.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)
            }
            .padding(24)

            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }

            Form {
                Section("来源") {
                    TextField("SVN 仓库 URL", text: $sourceURL)
                    Picker("模式", selection: $mode) {
                        Text("快照迁移").tag(GitMigrationMode.snapshot)
                        Text("历史保真").tag(GitMigrationMode.historyPreserving)
                    }
                    TextField("目标目录", text: $destinationPath)
                    Button("选择目录…") { pickDestination() }
                }

                switch step {
                case .analyze:
                    analyzeSection
                case .authors:
                    authorsSection
                case .cleanup:
                    cleanupSection
                case .execute:
                    executeSection
                case .sync:
                    syncSection
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 8)
        }
        .task { await bootstrap() }
        .onChange(of: workspaceController.selectedID) { _, _ in
            if let url = workspaceController.selectedRecord?.repoURL, sourceURL.isEmpty {
                sourceURL = url
            }
        }
    }

    @ViewBuilder
    private var analyzeSection: some View {
        Section("源分析") {
            Button("开始分析") { Task { await runAnalyze() } }
            if let analysis = analysisVM?.analysis {
                LabeledContent("revision 数", value: "\(analysis.totalRevisionCount)")
                LabeledContent("作者数", value: "\(analysis.authors.count)")
                LabeledContent("布局", value: analysis.layout.kind == .standard ? "标准" : "自定义")
                LabeledContent("git", value: analysis.environment.git.isAvailable ? "可用" : "缺失")
                LabeledContent("git-svn", value: analysis.environment.gitSvn.isAvailable ? "可用" : "缺失")
                if let latest = analysis.latestRevision {
                    LabeledContent("最新", value: "r\(latest.value)")
                }
            }
            if case .error(let message) = analysisVM?.state {
                Text(message).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var authorsSection: some View {
        Section("Authors 映射（历史保真必填）") {
            if mode == .snapshot {
                Text("快照模式无需 authors 映射。")
                    .foregroundStyle(.secondary)
            } else if let authorVM {
                Text("覆盖 \(authorVM.coverage.coveredCount)/\(authorVM.coverage.totalCount)")
                if !authorVM.aiPendingReviewUsernames.isEmpty {
                    Text("AI 推断待复核：\(authorVM.aiPendingReviewUsernames.count) 人（编辑单元格即视为已复核）")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack {
                    TextField("公司邮箱域名", text: $authorEmailDomain)
                        .textFieldStyle(.roundedBorder)
                    Button(authorVM.state == .inferring ? "推断中…" : "AI 批量推断") {
                        Task {
                            let privacy = await session.currentAIPrivacy()
                            await authorVM.inferWithAI(
                                emailDomain: authorEmailDomain,
                                privacySettings: privacy,
                                inferrer: session.aiAuthorMappingInferrer
                            )
                            if case .error(let message) = authorVM.state {
                                statusText = "AI 推断失败：\(message)"
                            } else {
                                statusText = "AI 已填充 \(authorVM.aiPendingReviewUsernames.count) 条，请人工复核"
                            }
                        }
                    }
                    .disabled(authorVM.state == .inferring || authorVM.mappings.isEmpty)
                }
                ForEach(authorVM.mappings, id: \.svnUsername) { mapping in
                    HStack {
                        Text(mapping.svnUsername).frame(width: 120, alignment: .leading)
                        if authorVM.aiPendingReviewUsernames.contains(mapping.svnUsername) {
                            Text("AI")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                        }
                        TextField(
                            "Git Name",
                            text: Binding(
                                get: { mapping.gitName },
                                set: { authorVM.updateMapping(svnUsername: mapping.svnUsername, gitName: $0, gitEmail: mapping.gitEmail) }
                            )
                        )
                        TextField(
                            "Email",
                            text: Binding(
                                get: { mapping.gitEmail },
                                set: { authorVM.updateMapping(svnUsername: mapping.svnUsername, gitName: mapping.gitName, gitEmail: $0) }
                            )
                        )
                        if authorVM.aiPendingReviewUsernames.contains(mapping.svnUsername) {
                            Button("确认") {
                                authorVM.markAISuggestionReviewed(svnUsername: mapping.svnUsername)
                            }
                        }
                    }
                }
                if !authorVM.canStartMigration, mode == .historyPreserving {
                    Text("映射未 100% 覆盖，禁止开始历史迁移。")
                        .foregroundStyle(.orange)
                }
            } else {
                Text("请先完成源分析。")
            }
        }
    }

    @ViewBuilder
    private var cleanupSection: some View {
        Section("清理策略") {
            Button("扫描大文件 / 生成 .gitignore 建议") { Task { await runCleanupPlan() } }
            if let plan = cleanupPlan {
                Text("大文件警告：\(plan.largeFiles.count)")
                ForEach(plan.largeFiles.prefix(20), id: \.path) { file in
                    Text("\(file.path) (\(file.sizeBytes) bytes)")
                        .font(.caption)
                }
                Text("建议 .gitignore：")
                    .font(.headline)
                TextEditor(text: .constant(plan.gitIgnoreContents))
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 120)
            }
        }
    }

    @ViewBuilder
    private var executeSection: some View {
        Section("执行迁移") {
            if mode == .snapshot {
                TextField("首次提交说明", text: $commitMessage)
            }
            Button(mode == .snapshot ? "执行快照迁移" : "执行历史保真迁移") {
                Task { await runMigrate() }
            }
            .disabled(destinationPath.isEmpty || sourceURL.isEmpty)
            .keyboardShortcut(.defaultAction)

            if case .running = migrateVM?.state {
                ProgressView("迁移进行中…")
            }
            if case .completed(let report) = migrateVM?.state {
                Text("完成：\(report.destinationPath)")
                    .foregroundStyle(.green)
                Text("步骤：\(report.completedSteps.map { String(describing: $0) }.joined(separator: ", "))")
                    .font(.caption)
            }
            if case .error(let message) = migrateVM?.state {
                Text(message).foregroundStyle(.red)
            }
        }

        if mode == .historyPreserving {
            Section("Revision 对账（NFR-14）") {
                Button("运行对账") {
                    Task { await runReconciliation() }
                }
                .disabled(destinationPath.isEmpty)

                if case .running = reconciliationVM?.state {
                    ProgressView("对账中…")
                }
                if let report = reconciliationVM?.report {
                    LabeledContent("源 revision", value: "\(report.sourceRevisionCount)")
                    LabeledContent("已迁移", value: "\(report.migratedRevisionCount)")
                    if report.isConsistent {
                        Text("对账一致，可进入同步步骤。")
                            .foregroundStyle(.green)
                    } else {
                        Text("对账失败：禁止进入同步，请先修复缺失/多余 revision。")
                            .foregroundStyle(.red)
                        if !report.missingRevisions.isEmpty {
                            Text("缺失：\(report.missingRevisions.prefix(20).map { "r\($0.value)" }.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if !report.unexpectedRevisions.isEmpty {
                            Text("多余：\(report.unexpectedRevisions.prefix(20).map { "r\($0.value)" }.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                if case .error(let message) = reconciliationVM?.state {
                    Text(message).foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        Section("过渡期增量同步") {
            TextField("目标 remote（可选，如 origin）", text: $targetRemote)
            Button("注册当前迁移并同步一次") {
                Task { await registerAndSync() }
            }
            Button("刷新同步记录") {
                Task { await syncVM?.loadRecords() }
            }
            List(syncVM?.records ?? []) { record in
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.sourceURL).font(.headline)
                    Text(record.repositoryPath).font(.caption)
                    Text("上次同步：\(record.lastSyncedAt?.formatted() ?? "从未")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("立即同步") {
                            Task { await syncVM?.sync(record) }
                        }
                        Toggle(
                            "定时",
                            isOn: Binding(
                                get: { record.isScheduledSyncEnabled },
                                set: { enabled in
                                    Task {
                                        await syncVM?.configureSchedule(
                                            record,
                                            isEnabled: enabled,
                                            intervalMinutes: record.syncIntervalMinutes ?? 60
                                        )
                                    }
                                }
                            )
                        )
                    }
                }
            }
            .frame(minHeight: 180)
            if case .completed(let report) = syncVM?.state {
                Text("同步完成，步骤 \(report.completedSteps.count)")
                    .foregroundStyle(.green)
            }
            if case .error(let message) = syncVM?.state {
                Text(message).foregroundStyle(.red)
            }
        }
    }

    private func bootstrap() async {
        analysisVM = GitMigrationSourceAnalysisViewModel(provider: session.gitMigrationSourceAnalyzer)
        authorVM = GitMigrationAuthorMappingViewModel(mapper: GitMigrationAuthorMapper())
        migrateVM = GitMigrationViewModel(provider: session.gitMigrationService)
        reconciliationVM = GitMigrationRevisionReconciliationViewModel(provider: session.gitMigrationService)
        syncVM = GitMigrationSyncViewModel(provider: session.gitMigrationSyncService)
        await syncVM?.loadRecords()
        if let url = workspaceController.selectedRecord?.repoURL {
            sourceURL = url
        }
    }

    private func runAnalyze() async {
        guard let analysisVM else { return }
        await analysisVM.analyze(repositoryRoot: sourceURL)
        if let analysis = analysisVM.analysis {
            authorVM?.loadAuthors(analysis.authors)
            statusText = "分析完成：\(analysis.totalRevisionCount) revisions / \(analysis.authors.count) authors"
            step = mode == .historyPreserving ? .authors : .cleanup
        } else if case .error(let message) = analysisVM.state {
            statusText = message
        }
    }

    private func runCleanupPlan() async {
        do {
            let entries = try await session.svnService.list(url: sourceURL, depth: .immediates, auth: nil)
            cleanupPlan = try GitMigrationCleanupPlanner().plan(entries: entries)
            statusText = "清理计划已生成"
        } catch {
            statusText = "清理扫描失败：\(error.localizedDescription)"
        }
    }

    private func runMigrate() async {
        guard let migrateVM else { return }
        let destination = URL(fileURLWithPath: destinationPath)
        if mode == .snapshot {
            await migrateVM.snapshotMigrate(
                sourceURL: sourceURL,
                destination: destination,
                commitMessage: commitMessage
            )
        } else {
            guard let authorVM, authorVM.canStartMigration else {
                statusText = "authors 映射未完成"
                step = .authors
                return
            }
            let layout = analysisVM?.analysis?.layout ?? GitMigrationRepositoryLayout(
                kind: .standard,
                trunkPath: "trunk",
                branchesPath: "branches",
                tagsPath: "tags",
                confidence: 1
            )
            await migrateVM.historyMigrate(
                sourceURL: sourceURL,
                destination: destination,
                layout: layout,
                authorMappings: authorVM.mappings
            )
        }

        if case .completed = migrateVM.state {
            if mode == .historyPreserving {
                await runReconciliation()
                if reconciliationVM?.report?.isConsistent != true {
                    statusText = "迁移完成但对账未通过，已阻断进入同步"
                    return
                }
            }
            statusText = "迁移成功"
            step = .sync
            let remote = targetRemote.trimmingCharacters(in: .whitespacesAndNewlines)
            await syncVM?.registerMigration(
                sourceURL: sourceURL,
                repository: destination,
                targetRemote: remote.isEmpty ? nil : remote
            )
        } else if case .error(let message) = migrateVM.state {
            statusText = message
        }
    }

    private func runReconciliation() async {
        guard let reconciliationVM else { return }
        let sourceRevisions = analysisVM?.analysis?.sourceRevisions ?? []
        guard !sourceRevisions.isEmpty else {
            statusText = "缺少源 revision 列表，请先完成源分析"
            step = .analyze
            return
        }
        await reconciliationVM.reconcile(
            sourceRevisions: sourceRevisions,
            gitRepository: URL(fileURLWithPath: destinationPath)
        )
        if case .error(let message) = reconciliationVM.state {
            statusText = "对账失败：\(message)"
        } else if let report = reconciliationVM.report {
            statusText = report.isConsistent
                ? "对账一致（\(report.migratedRevisionCount)/\(report.sourceRevisionCount)）"
                : "对账不一致：缺失 \(report.missingRevisions.count) / 多余 \(report.unexpectedRevisions.count)"
        }
    }

    private func registerAndSync() async {
        if mode == .historyPreserving, reconciliationVM?.report?.isConsistent != true {
            statusText = "对账未通过，禁止同步（NFR-14）"
            step = .execute
            await runReconciliation()
            return
        }
        guard let syncVM else { return }
        let destination = URL(fileURLWithPath: destinationPath)
        let remote = targetRemote.trimmingCharacters(in: .whitespacesAndNewlines)
        await syncVM.registerMigration(
            sourceURL: sourceURL,
            repository: destination,
            targetRemote: remote.isEmpty ? nil : remote
        )
        if let record = syncVM.records.first(where: { $0.repositoryPath == destination.path }) {
            await syncVM.sync(record)
        }
    }

    private func pickDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "选择目标"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destinationPath = url.appendingPathComponent("migrated-git").path
    }
}
