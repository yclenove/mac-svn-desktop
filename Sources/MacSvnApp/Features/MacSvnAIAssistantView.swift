import SwiftUI
import MacSvnCore

/// AI 助手 Chat：本地 SVN tool + LLM；写操作走确认门并展示审计。
public struct MacSvnAIAssistantView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession

    @State private var viewModel: AIAssistantChatViewModel?
    @State private var showAudit = false

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
            HStack(spacing: 8) {
                Text("AI 助手")
                    .font(.headline)
                Spacer(minLength: 8)
                Toggle("审计", isOn: $showAudit)
                    .toggleStyle(.switch)
                    .disabled(isAssistantBusy)
                Button {
                    Task { await refreshAssistantContext() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .frame(
                    minWidth: MacSvnSpecializedToolsMetrics.iconButtonMinSide,
                    minHeight: MacSvnSpecializedToolsMetrics.iconButtonMinSide
                )
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityIdentifier("macSvn.st.aiAssistant.refresh")
                .accessibilityLabel(Text("刷新 AI 助手上下文"))
                .disabled(isAssistantBusy || viewModel == nil)
                .help("刷新工具审计与助手上下文")
            }
            .frame(height: MacSvnSpecializedToolsMetrics.toolbarHeight)
            .padding(.horizontal, 12)

            if let feedback = assistantFeedbackText {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(assistantFeedbackIsError ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: MacSvnSpecializedToolsMetrics.feedbackBarHeight)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("macSvn.st.aiAssistant.feedback")
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
            await consumePendingQueryIfNeeded()
        }
        .onChange(of: navigator.pendingAIChatQuery) { _, _ in
            Task { await consumePendingQueryIfNeeded() }
        }
    }

    private var isAssistantBusy: Bool {
        viewModel?.state == .thinking
    }

    private var assistantFeedbackIsError: Bool {
        if case .error = viewModel?.state { return true }
        return false
    }

    private var assistantFeedbackText: String? {
        if workspaceController.selectedRecord == nil {
            return "提示：选择工作副本后可使用 status/diff/log 等本地指令。"
        }
        switch viewModel?.state {
        case .thinking:
            return "正在思考或执行工具…"
        case .awaitingConfirmation:
            return "写操作待确认：确认后才会执行，并写入审计。"
        case .error(let message):
            return message
        case .idle, .none:
            return nil
        }
    }

    private func refreshAssistantContext() async {
        await viewModel?.refreshAudit()
    }

    private func consumePendingQueryIfNeeded() async {
        guard let query = navigator.consumePendingAIChatQuery(), let viewModel else { return }
        viewModel.draft = query
        await viewModel.sendDraft(workingCopyPath: workspaceController.selectedRecord?.localPath)
    }

    @ViewBuilder
    private var chatPane: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    .disabled(isAssistantBusy)
                    Button("取消", role: .cancel) {
                        Task { await viewModel?.cancelPendingTool() }
                    }
                    .disabled(isAssistantBusy)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            HStack(alignment: .bottom) {
                TextEditor(text: Binding(
                    get: { viewModel?.draft ?? "" },
                    set: { viewModel?.draft = $0 }
                ))
                .font(.body)
                .frame(minHeight: 60, maxHeight: 120)
                .border(Color.secondary.opacity(0.3))
                .disabled(isAssistantBusy)

                Button("发送") {
                    Task {
                        await viewModel?.sendDraft(
                            workingCopyPath: workspaceController.selectedRecord?.localPath
                        )
                    }
                }
                .disabled(viewModel == nil || isAssistantBusy)
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
