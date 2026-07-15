import SwiftUI
import MacSvnCore

/// Merge 向导：dry-run 预览 + 执行合并。
public struct MacSvnMergeWizardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession

    private enum MergeMode: String, CaseIterable, Identifiable {
        case revisionRange = "修订范围"
        case twoTrees = "两棵树"
        case reintegrate = "重新整合"
        var id: String { rawValue }
    }

    @State private var mergeMode: MergeMode = .revisionRange
    @State private var sourceURL = ""
    @State private var targetURL = ""
    @State private var startRevision = ""
    @State private var endRevision = ""
    @State private var viewModel: MergeWizardViewModel?
    @State private var statusText: LocalizedStringKey?

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
        VStack(alignment: .leading, spacing: 16) {
            Text("合并向导")
                .font(.largeTitle.weight(.semibold))

            if workspaceController.selectedRecord == nil {
                ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
            } else {
                Form {
                    Picker("合并类型", selection: $mergeMode) {
                        ForEach(MergeMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                        }
                    }
                    TextField("来源 URL / 分支", text: $sourceURL)
                    if mergeMode == .twoTrees {
                        TextField("目标 URL / 分支", text: $targetURL)
                    } else if mergeMode == .revisionRange {
                        HStack {
                            TextField("起始 revision（可选）", text: $startRevision)
                            TextField("结束 revision（可选）", text: $endRevision)
                        }
                    }
                    HStack {
                        Button("Dry-run 预览") {
                            Task { await run(dryRun: true) }
                        }
                        Button("Unified Diff") {
                            Task { await runDiff() }
                        }
                        .disabled(!canPreviewDiff)
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
                            ForEach(Array(summary.affectedPaths.prefix(12).enumerated()), id: \.offset) { _, affected in
                                HStack(spacing: 6) {
                                    Text(mergeActionSymbol(affected.action))
                                        .font(.caption.monospaced().weight(.semibold))
                                        .foregroundStyle(mergeActionColour(affected.action))
                                    Text(affected.path)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if let diff = viewModel?.unifiedDiff {
                    ScrollView {
                        Text(DiffPerformanceLimits.truncatedDisplayText(diff))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxHeight: 260)
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
            Spacer()
        }
        .padding(24)
        .task {
            viewModel = MergeWizardViewModel(provider: session.svnService)
            if let url = workspaceController.selectedRecord?.repoURL {
                sourceURL = url
                targetURL = url
            }
            if let pendingSourceURL = navigator.consumePendingMergeSourceURL(),
               !pendingSourceURL.isEmpty {
                sourceURL = pendingSourceURL
            }
        }
    }

    private func run(dryRun: Bool) async {
        guard let record = workspaceController.selectedRecord,
              let viewModel
        else { return }

        let range: RevisionRange?
        if mergeMode == .revisionRange {
            let start = startRevision.trimmingCharacters(in: .whitespacesAndNewlines)
            let end = endRevision.trimmingCharacters(in: .whitespacesAndNewlines)
            if start.isEmpty, end.isEmpty {
                range = nil
            } else if let startValue = Int(start), startValue >= 0,
                      let endValue = Int(end), endValue >= 0 {
                range = RevisionRange(start: Revision(startValue), end: Revision(endValue))
            } else {
                statusText = "失败：起始和结束 revision 必须同时填写非负整数"
                return
            }
        } else {
            range = nil
        }

        let wc = URL(fileURLWithPath: record.localPath)
        let summary: MergeSummary?
        if mergeMode == .twoTrees {
            if dryRun {
                await viewModel.previewTwoTrees(wc: wc, from: sourceURL, to: targetURL)
            } else {
                await viewModel.mergeTwoTrees(wc: wc, from: sourceURL, to: targetURL)
            }
            summary = dryRun ? viewModel.previewSummary : viewModel.mergeSummary
        } else if mergeMode == .reintegrate {
            if dryRun {
                await viewModel.previewReintegrate(wc: wc, source: sourceURL)
            } else {
                await viewModel.reintegrate(wc: wc, source: sourceURL)
            }
            summary = dryRun ? viewModel.previewSummary : viewModel.mergeSummary
        } else if dryRun {
            await viewModel.preview(wc: wc, source: sourceURL, range: range)
            summary = viewModel.previewSummary
        } else {
            await viewModel.merge(wc: wc, source: sourceURL, range: range)
            summary = viewModel.mergeSummary
        }

        switch viewModel.state {
        case .previewReady:
            statusText = "预览完成（未改动工作副本）"
        case .completed:
            if let summary, summary.conflicted > 0 {
                let paths = summary.affectedPaths
                    .filter { $0.action == .conflicted }
                    .map(\.path)
                navigator.openMergeConflicts(paths: paths)
                statusText = "合并产生冲突，已打开冲突工作区"
            } else {
                statusText = "合并完成"
            }
        case .error(let message):
            statusText = "失败：\(message)"
        default:
            break
        }
    }

    private func mergeActionColour(_ action: MergeAction) -> Color {
        let palette = session.settingsSnapshot.changeColours
        guard let role = palette.role(for: action) else { return .secondary }
        return svnChangeColour(palette: palette, role: role, colorScheme: colorScheme)
    }

    private func mergeActionSymbol(_ action: MergeAction) -> String {
        switch action {
        case .added: return "A"
        case .updated: return "U"
        case .deleted: return "D"
        case .conflicted: return "C"
        case .merged: return "G"
        case .existed: return "E"
        case .replaced: return "R"
        case .unknown(let value): return String(value)
        }
    }

    private var canPreviewDiff: Bool {
        guard !sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if mergeMode == .twoTrees {
            return !targetURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if mergeMode == .reintegrate {
            return false
        }
        return parsedRevisionRange != nil
    }

    private func runDiff() async {
        guard let record = workspaceController.selectedRecord, let viewModel else { return }
        let wc = URL(fileURLWithPath: record.localPath)
        if mergeMode == .twoTrees {
            await viewModel.previewTwoTreeUnifiedDiff(wc: wc, from: sourceURL, to: targetURL)
        } else if let range = parsedRevisionRange {
            await viewModel.previewUnifiedDiff(
                wc: wc,
                source: sourceURL,
                range: range
            )
        }
        if case .diffReady = viewModel.state {
            statusText = "Unified Diff 预览完成"
        } else if case .error(let message) = viewModel.state {
            statusText = "Diff 失败：\(message)"
        }
    }

    private var parsedRevisionRange: RevisionRange? {
        let start = startRevision.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = endRevision.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let startValue = Int(start), startValue >= 0,
              let endValue = Int(end), endValue >= 0
        else { return nil }
        return RevisionRange(start: Revision(startValue), end: Revision(endValue))
    }
}
