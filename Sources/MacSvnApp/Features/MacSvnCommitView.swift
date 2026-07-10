import SwiftUI
import MacSvnCore

/// 提交页：接 CommitViewModel + 提交说明历史 + Commit Guard 警告。
public struct MacSvnCommitView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let session: MacSvnAppSession

    @State private var viewModel: CommitViewModel?
    @State private var statusText: String?

    public init(workspaceController: MacSvnWorkspaceController, session: MacSvnAppSession) {
        self.workspaceController = workspaceController
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("提交")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Button("刷新候选") {
                    Task { await reloadCandidates() }
                }
                Button("提交") {
                    Task { await commit(skipWarnings: false) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel?.canCommit != true)
            }
            .padding(24)

            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
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
}
