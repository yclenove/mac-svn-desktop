import SwiftUI
import MacSvnCore

/// 提交页：接 CommitViewModel + 提交说明历史 + Commit Guard 警告。
public struct MacSvnCommitView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let session: MacSvnAppSession
    private let embedded: Bool

    @State private var viewModel: CommitViewModel?
    @State private var statusText: String?

    public init(
        workspaceController: MacSvnWorkspaceController,
        session: MacSvnAppSession,
        embedded: Bool = false
    ) {
        self.workspaceController = workspaceController
        self.session = session
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
        .task { await reloadCandidates() }
    }

    @ViewBuilder
    private var content: some View {
        if workspaceController.selectedRecord == nil {
            ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
        } else if let viewModel {
            HSplitView {
                List {
                    ForEach(viewModel.candidateStatuses, id: \.path) { status in
                        Toggle(isOn: Binding(
                            get: { viewModel.selectedPaths.contains(status.path) },
                            set: { viewModel.setSelected($0, for: status.path) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(status.path)
                                Text(status.itemStatus.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(status.itemStatus == .conflicted || status.isTreeConflict)
                    }
                }
                .frame(minWidth: 280)

                VStack(alignment: .leading, spacing: 12) {
                    Text("提交说明")
                        .font(.headline)
                    TextEditor(text: Binding(
                        get: { viewModel.message },
                        set: { viewModel.message = $0 }
                    ))
                    .font(.body)
                    .frame(minHeight: 160)
                    .border(Color.secondary.opacity(0.3))

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

                    if case .error(let message) = viewModel.state {
                        Text(message)
                            .foregroundStyle(.red)
                    }

                    aiStatusSection(viewModel)

                    Spacer()
                }
                .padding()
                .frame(minWidth: 360)
            }
        } else {
            ProgressView("加载变更…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func reloadCandidates() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            viewModel = nil
            return
        }
        let wc = URL(fileURLWithPath: record.localPath)
        do {
            let statuses = try await session.svnService.status(wc: wc)
            let vm = CommitViewModel(
                workingCopy: wc,
                statuses: statuses,
                commitProvider: session.svnService,
                statusProvider: session.svnService,
                aiCommitMessageGenerator: session.aiCommitMessageGenerator,
                aiPreCommitReviewer: session.aiPreCommitReviewer,
                commitMessageHistoryProvider: session.commitMessageHistoryStore
            )
            viewModel = vm
            await vm.loadRecentMessages()
            statusText = "候选 \(vm.candidateStatuses.count) 项"
        } catch {
            statusText = "加载失败：\(error.localizedDescription)"
            viewModel = nil
        }
    }

    private func commit(skipWarnings: Bool) async {
        guard let viewModel else { return }
        await viewModel.commit(auth: nil, skipGuardWarnings: skipWarnings)
        if case .committed(let revision) = viewModel.state {
            statusText = "提交成功 r\(revision.value)"
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
}
