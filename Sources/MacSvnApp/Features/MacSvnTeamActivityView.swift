import SwiftUI
import MacSvnCore

/// 团队活动：近期提交聚合 + 锁卡片。
public struct MacSvnTeamActivityView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let session: MacSvnAppSession

    @State private var viewModel: TeamActivityViewModel?
    @State private var statusText: LocalizedStringKey?

    public init(workspaceController: MacSvnWorkspaceController, session: MacSvnAppSession) {
        self.workspaceController = workspaceController
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("团队动态")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Button("刷新") {
                    Task { await reload() }
                }
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
        .task { await reload() }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await reload() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if workspaceController.selectedRecord == nil {
            ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
        } else if let viewModel {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("加载团队活动…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let message):
                ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(message))
            case .loaded:
                if let summary = viewModel.summary {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            sectionTitle("作者贡献")
                            ForEach(summary.authorStats, id: \.author) { stat in
                                HStack {
                                    Text(stat.author)
                                    Spacer()
                                    Text("\(stat.commitCount) 次提交")
                                        .foregroundStyle(.secondary)
                                }
                            }

                            sectionTitle("活跃路径")
                            ForEach(summary.activePaths, id: \.path) { path in
                                HStack {
                                    Text(path.path)
                                    Spacer()
                                    Text("\(path.changeCount)")
                                        .foregroundStyle(.secondary)
                                }
                            }

                            sectionTitle("按日提交热力图")
                            TeamActivityHeatmapView(days: summary.dailyCommits)
                                .accessibilityIdentifier("team-activity-heatmap")

                            sectionTitle("锁")
                            if summary.lockCards.isEmpty {
                                Text("当前无锁").foregroundStyle(.secondary)
                            } else {
                                ForEach(summary.lockCards, id: \.target) { lock in
                                    VStack(alignment: .leading) {
                                        Text(lock.target).font(.headline)
                                        Text("\(lock.owner ?? "未知") · \(lock.comment ?? "")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(24)
                    }
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.title3.weight(.semibold))
    }

    private func reload() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            viewModel = nil
            return
        }
        let wc = URL(fileURLWithPath: record.localPath)
        let vm = TeamActivityViewModel(
            workingCopy: wc,
            target: "",
            logProvider: session.svnService,
            lockProvider: session.svnService
        )
        viewModel = vm
        let settings = await session.settingsStore.settings()
        let from = Revision(max(1, (record.revision?.value ?? 1) - settings.logBatchSize))
        await vm.load(from: from, batch: settings.logBatchSize, lockTargets: ["."])
        statusText = "已加载"
    }
}
