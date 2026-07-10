import SwiftUI
import MacSvnCore

/// AI 助手 Chat：本地 SVN tool + LLM；写操作走确认门并展示审计。
public struct MacSvnAIAssistantView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let session: MacSvnAppSession

    @State private var viewModel: AIAssistantChatViewModel?
    @State private var showAudit = false

    public init(workspaceController: MacSvnWorkspaceController, session: MacSvnAppSession) {
        self.workspaceController = workspaceController
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AI 助手")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Toggle("审计", isOn: $showAudit)
                    .toggleStyle(.switch)
                Button("打开 Provider 设置") {
                    // 用户可从侧边栏进入设置；此处提示路径
                }
                .hidden()
            }
            .padding(24)

            if workspaceController.selectedRecord == nil {
                Text("提示：选择工作副本后可使用 status/diff/log 等本地指令。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }

            HSplitView {
                chatPane
                if showAudit {
                    auditPane
                        .frame(minWidth: 240, idealWidth: 280)
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = AIAssistantChatViewModel(
                    llmClient: session.llmClient,
                    providerManager: session.aiProviderStore,
                    toolRegistry: session.aiToolRegistry,
                    auditStore: session.aiToolAuditStore
                )
            }
            await viewModel?.refreshAudit()
        }
    }

    @ViewBuilder
    private var chatPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel?.messages ?? []) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role == .user ? "你" : "助手")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(message.content)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            message.role == .user
                                ? Color.accentColor.opacity(0.08)
                                : Color(nsColor: .controlBackgroundColor)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(16)
            }

            if case .awaitingConfirmation = viewModel?.state {
                HStack {
                    Button("确认写操作") {
                        Task { await viewModel?.confirmPendingTool() }
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("取消", role: .cancel) {
                        Task { await viewModel?.cancelPendingTool() }
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack(alignment: .bottom) {
                TextEditor(text: Binding(
                    get: { viewModel?.draft ?? "" },
                    set: { viewModel?.draft = $0 }
                ))
                .font(.body)
                .frame(minHeight: 60, maxHeight: 120)
                .border(Color.secondary.opacity(0.3))

                Button("发送") {
                    Task {
                        await viewModel?.sendDraft(
                            workingCopyPath: workspaceController.selectedRecord?.localPath
                        )
                    }
                }
                .disabled(viewModel == nil || viewModel?.state == .thinking)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var auditPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("工具审计")
                .font(.headline)
                .padding([.top, .horizontal], 12)
            List(viewModel?.auditRecords ?? []) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.toolName).font(.subheadline.weight(.semibold))
                    Text(record.outcome.rawValue).font(.caption2)
                    if let summary = record.summary {
                        Text(summary).font(.caption).lineLimit(3)
                    }
                }
            }
        }
    }
}
