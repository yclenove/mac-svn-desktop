import SwiftUI
import MacSvnCore

/// Merge 向导：dry-run 预览 + 执行合并。
public struct MacSvnMergeWizardView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let session: MacSvnAppSession

    @State private var sourceURL = ""
    @State private var startRevision = ""
    @State private var endRevision = ""
    @State private var viewModel: MergeWizardViewModel?
    @State private var statusText: String?

    public init(workspaceController: MacSvnWorkspaceController, session: MacSvnAppSession) {
        self.workspaceController = workspaceController
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("合并向导")
                .font(.largeTitle.weight(.semibold))

            if workspaceController.selectedRecord == nil {
                ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
            } else {
                Form {
                    TextField("来源 URL / 分支", text: $sourceURL)
                    HStack {
                        TextField("起始 revision（可选）", text: $startRevision)
                        TextField("结束 revision（可选）", text: $endRevision)
                    }
                    HStack {
                        Button("Dry-run 预览") {
                            Task { await run(dryRun: true) }
                        }
                        Button("执行合并") {
                            Task { await run(dryRun: false) }
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .formStyle(.grouped)

                if let statusText {
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }

                if let summary = viewModel?.previewSummary ?? viewModel?.mergeSummary {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("结果摘要")
                            .font(.headline)
                        Text("更新 \(summary.updated) / 新增 \(summary.added) / 删除 \(summary.deleted) / 冲突 \(summary.conflicted) / 合并 \(summary.merged)")
                        if !summary.affectedPaths.isEmpty {
                            Text("影响路径：\(summary.affectedPaths.prefix(12).map(\.path).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Spacer()
        }
        .padding(24)
        .task {
            viewModel = MergeWizardViewModel(provider: session.svnService)
            if let url = workspaceController.selectedRecord?.repoURL {
                sourceURL = url
            }
        }
    }

    private func run(dryRun: Bool) async {
        guard let record = workspaceController.selectedRecord,
              let viewModel
        else { return }

        let range: RevisionRange?
        if let start = Int(startRevision), let end = Int(endRevision) {
            range = RevisionRange(start: Revision(start), end: Revision(end))
        } else {
            range = nil
        }

        let wc = URL(fileURLWithPath: record.localPath)
        if dryRun {
            await viewModel.preview(wc: wc, source: sourceURL, range: range)
        } else {
            await viewModel.merge(wc: wc, source: sourceURL, range: range)
        }

        switch viewModel.state {
        case .previewReady:
            statusText = "预览完成（未改动工作副本）"
        case .completed:
            statusText = "合并完成；如有冲突请前往「冲突合并」处理"
        case .error(let message):
            statusText = "失败：\(message)"
        default:
            break
        }
    }
}
