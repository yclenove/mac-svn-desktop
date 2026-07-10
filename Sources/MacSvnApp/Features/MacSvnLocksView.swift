import SwiftUI
import MacSvnCore

public struct MacSvnLocksView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let session: MacSvnAppSession

    @State private var paths: [String] = []
    @State private var selected: Set<String> = []
    @State private var viewModel: LockViewModel?
    @State private var message = ""
    @State private var statusText: String?

    public init(workspaceController: MacSvnWorkspaceController, session: MacSvnAppSession) {
        self.workspaceController = workspaceController
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("锁定")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                TextField("锁定注释", text: $message)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Button("刷新") { Task { await reload() } }
                Button("Lock") { Task { await viewModel?.lock(paths: Array(selected), message: message, force: false) } }
                    .disabled(selected.isEmpty)
                Button("Unlock") { Task { await viewModel?.unlock(paths: Array(selected), force: false) } }
                    .disabled(selected.isEmpty)
                Button("强制夺锁") {
                    Task { await viewModel?.lock(paths: Array(selected), message: message, force: true, confirmed: true) }
                }
                .disabled(selected.isEmpty)
            }
            .padding(24)

            if let statusText {
                Text(statusText).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24)
            }

            if workspaceController.selectedRecord == nil {
                ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
            } else {
                HSplitView {
                    MacSvnPathPicker(paths: paths, selection: $selected)
                        .frame(minWidth: 220)
                    List(viewModel?.locks ?? [], id: \.target) { lock in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lock.target).font(.headline)
                            Text("owner: \(lock.owner ?? "-")")
                                .font(.caption)
                            Text(lock.comment ?? "")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .task { await bootstrap() }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await bootstrap() }
        }
    }

    private func bootstrap() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            paths = []; viewModel = nil; return
        }
        let wc = URL(fileURLWithPath: record.localPath)
        paths = await MacSvnPathLoader.loadPaths(svnService: session.svnService, wc: wc)
        viewModel = LockViewModel(workingCopy: wc, provider: session.svnService)
        await reload()
    }

    private func reload() async {
        await viewModel?.load(targets: Array(selected))
        if case .error(let message) = viewModel?.state {
            statusText = message
        } else {
            statusText = "锁记录 \(viewModel?.locks.count ?? 0)"
        }
    }
}
