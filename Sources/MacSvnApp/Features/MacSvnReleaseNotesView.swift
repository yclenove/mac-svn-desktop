import SwiftUI
import MacSvnCore
import AppKit

/// AI Release Notes：从 WC 日志或外部带入条目生成 Markdown 草稿（FR-AI-05）。
public struct MacSvnReleaseNotesView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession

    @State private var viewModel: AIReleaseNotesViewModel?
    @State private var statusText: String?

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
            HStack {
                Text("AI Release Notes")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Button("加载最近日志") {
                    Task { await loadLogs() }
                }
                .disabled(workspaceController.selectedRecord == nil)
                Button("生成") {
                    Task { await generate() }
                }
                .disabled(viewModel?.entries.isEmpty != false || viewModel?.state == .generating)
                .keyboardShortcut(.defaultAction)
                Button("复制 Markdown") {
                    copyMarkdown()
                }
                .disabled(viewModel?.draft == nil)
            }
            .padding(24)

            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }

            Form {
                Section("参数") {
                    if let viewModel {
                        TextField("标题", text: Binding(
                            get: { viewModel.title },
                            set: { viewModel.title = $0 }
                        ))
                        Picker("模板", selection: Binding(
                            get: { viewModel.template },
                            set: { viewModel.template = $0 }
                        )) {
                            Text("标准 Markdown").tag(AIReleaseNotesTemplate.standardMarkdown)
                            Text("公司模板").tag(AIReleaseNotesTemplate.companyTemplate)
                        }
                        LabeledContent("日志条数", value: "\(viewModel.entries.count)")
                    }
                }

                Section("候选日志") {
                    if let viewModel, !viewModel.entries.isEmpty {
                        ForEach(viewModel.entries.prefix(40), id: \.revision.value) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("r\(entry.revision.value) · \(entry.author)")
                                    .font(.caption.weight(.semibold))
                                Text(entry.message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        if viewModel.entries.count > 40 {
                            Text("…另有 \(viewModel.entries.count - 40) 条")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Text("请加载日志，或从「日志」页带入当前过滤结果。")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("生成结果") {
                    if case .generating = viewModel?.state {
                        ProgressView("正在生成…")
                    } else if case .error(let message) = viewModel?.state {
                        Text(message).foregroundStyle(.red)
                    } else if let draft = viewModel?.draft {
                        Text(draft.markdown)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("尚未生成")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 8)
        }
        .task { await bootstrap() }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await loadLogs() }
        }
        .onChange(of: navigator.pendingReleaseNotesEntries?.count) { _, _ in
            applyPendingEntries()
        }
    }

    private func bootstrap() async {
        if viewModel == nil {
            viewModel = AIReleaseNotesViewModel(
                logProvider: session.svnService,
                generator: session.aiReleaseNotesGenerator
            )
        }
        if applyPendingEntries() {
            return
        }
        if workspaceController.selectedRecord != nil {
            await loadLogs()
        }
    }

    @discardableResult
    private func applyPendingEntries() -> Bool {
        guard let pending = navigator.pendingReleaseNotesEntries, !pending.isEmpty, let viewModel else {
            return false
        }
        viewModel.loadEntries(pending)
        navigator.pendingReleaseNotesEntries = nil
        statusText = "已从日志页带入 \(pending.count) 条"
        return true
    }

    private func loadLogs() async {
        guard let record = workspaceController.selectedRecord, let viewModel else { return }
        await viewModel.loadRecentLogs(wc: URL(fileURLWithPath: record.localPath), batch: 50)
        switch viewModel.state {
        case .ready:
            statusText = "已加载 \(viewModel.entries.count) 条日志"
        case .error(let message):
            statusText = message
        case .idle:
            statusText = "无日志"
        default:
            break
        }
    }

    private func generate() async {
        guard let viewModel else { return }
        let privacy = await session.currentAIPrivacy()
        await viewModel.generate(privacySettings: privacy)
        switch viewModel.state {
        case .completed(let draft):
            statusText = "已生成（\(draft.entryCount) 条日志，provider \(draft.providerID.uuidString.prefix(8))）"
        case .error(let message):
            statusText = "生成失败：\(message)"
        default:
            break
        }
    }

    private func copyMarkdown() {
        guard let markdown = viewModel?.draft?.markdown else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        statusText = "Markdown 已复制到剪贴板"
    }
}
