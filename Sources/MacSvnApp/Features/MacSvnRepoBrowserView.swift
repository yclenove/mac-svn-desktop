import SwiftUI
import MacSvnCore
import AppKit

/// 仓库浏览器：远端目录懒加载、预览、收藏、Checkout 与远端写操作（mkdir/删/复制/移动）。
public struct MacSvnRepoBrowserView: View {
    private let session: MacSvnAppSession
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator

    @State private var browserVM: RepoBrowserViewModel?
    @State private var checkoutVM: CheckoutViewModel?
    @State private var rootURL: String = ""
    @State private var selectedEntry: RemoteEntry?
    @State private var selectedDepth: SvnDepth = .infinity
    @State private var checkoutRevisionText = ""
    @State private var checkoutIgnoreExternals = false
    @State private var statusText: String?
    @State private var previewText: String = ""

    /// 远端写操作弹窗状态（均需提交说明，对应 FR-RB-06）。
    @State private var showRemoteWriteSheet = false
    @State private var remoteWriteKind: RemoteWriteKind = .mkdir
    @State private var remoteWriteName = ""
    @State private var remoteWriteDestination = ""
    @State private var remoteWriteMessage = ""

    private enum RemoteWriteKind: String, Identifiable {
        case mkdir = "新建目录"
        case delete = "删除"
        case copy = "复制"
        case move = "移动"

        var id: String { rawValue }
    }

    public init(
        session: MacSvnAppSession,
        workspaceController: MacSvnWorkspaceController,
        navigator: MacSvnAppNavigator
    ) {
        self.session = session
        self.workspaceController = workspaceController
        self.navigator = navigator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            HSplitView {
                sidebar
                    .frame(minWidth: 220)
                centerPane
                    .frame(minWidth: 280)
                detailPane
                    .frame(minWidth: 280)
            }
        }
        .task { await bootstrap() }
        .onChange(of: navigator.pendingBrowseURL) { _, _ in
            Task { await consumePendingBrowse() }
        }
        .sheet(isPresented: $showRemoteWriteSheet) {
            remoteWriteSheet
        }
    }

    private var header: some View {
        HStack {
            Text("仓库浏览器")
                .font(.largeTitle.weight(.semibold))
            Spacer()
            TextField("仓库 URL", text: $rootURL)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)
            Button("浏览") {
                Task { await openRoot() }
            }
            Button("收藏") {
                Task { await browserVM?.addBookmark(url: rootURL) }
            }
            .disabled(rootURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(24)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("收藏")
                .font(.headline)
                .padding(.horizontal, 12)
            List {
                ForEach(browserVM?.bookmarks ?? []) { bookmark in
                    Button(bookmark.name) {
                        rootURL = bookmark.url
                        Task { await openRoot() }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var centerPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            remoteWriteToolbar
            if let statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            List(selection: Binding(
                get: { selectedEntry?.path },
                set: { path in
                    guard let path, let browserVM else { return }
                    selectedEntry = browserVM.children(of: rootURL).first(where: { $0.path == path })
                    Task { await previewSelected() }
                }
            )) {
                ForEach(browserVM?.children(of: rootURL) ?? [], id: \.path) { entry in
                    HStack {
                        Image(systemName: entry.kind == .directory ? "folder" : "doc")
                        Text(entry.name)
                        Spacer()
                        if let revision = entry.revision {
                            Text("r\(revision.value)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(entry.path)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedEntry = entry
                        Task {
                            if entry.kind == .directory {
                                let childURL = join(rootURL, entry.path)
                                await browserVM?.loadChildren(of: childURL)
                                rootURL = childURL
                            } else {
                                await previewSelected()
                            }
                        }
                    }
                }
            }
        }
    }

    private var remoteWriteToolbar: some View {
        HStack(spacing: 8) {
            Button("新建目录") { presentRemoteWrite(.mkdir) }
            Button("删除") { presentRemoteWrite(.delete) }
                .disabled(selectedEntry == nil)
            Button("复制") { presentRemoteWrite(.copy) }
                .disabled(selectedEntry == nil)
            Button("移动") { presentRemoteWrite(.move) }
                .disabled(selectedEntry == nil)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("详情")
                .font(.headline)
            if let selectedEntry {
                LabeledContent("名称", value: selectedEntry.name)
                LabeledContent("类型", value: selectedEntry.kind == .directory ? "目录" : "文件")
                if let author = selectedEntry.author {
                    LabeledContent("作者", value: author)
                }

                Picker("检出深度", selection: $selectedDepth) {
                    Text("empty").tag(SvnDepth.empty)
                    Text("files").tag(SvnDepth.files)
                    Text("immediates").tag(SvnDepth.immediates)
                    Text("infinity").tag(SvnDepth.infinity)
                }
                TextField("检出修订（留空=HEAD）", text: $checkoutRevisionText)
                Toggle("忽略外部项", isOn: $checkoutIgnoreExternals)

                Button("Checkout 到…") {
                    presentCheckout(for: selectedEntry)
                }
                .disabled(selectedEntry.kind != .directory && selectedDepth != .files)

                ScrollView {
                    Text(previewText.isEmpty ? "选择文件可预览内容" : previewText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .border(Color.secondary.opacity(0.2))
            } else {
                Text("选择远端条目查看详情")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private var remoteWriteSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(remoteWriteKind.rawValue)
                .font(.title2.weight(.semibold))
            Text("远端写操作会立即提交到仓库，必须填写提交说明。")
                .font(.caption)
                .foregroundStyle(.secondary)

            switch remoteWriteKind {
            case .mkdir:
                TextField("目录名", text: $remoteWriteName)
                    .textFieldStyle(.roundedBorder)
            case .delete:
                if let selectedEntry {
                    LabeledContent("将删除", value: selectedEntry.name)
                }
            case .copy, .move:
                if let selectedEntry {
                    LabeledContent("源", value: selectedEntry.name)
                }
                TextField("目标 URL", text: $remoteWriteDestination)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("提交说明（必填）", text: $remoteWriteMessage)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("取消") { showRemoteWriteSheet = false }
                Button("执行并提交") {
                    Task { await executeRemoteWrite() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmitRemoteWrite)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }

    private var canSubmitRemoteWrite: Bool {
        let messageOK = !remoteWriteMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard messageOK else { return false }
        switch remoteWriteKind {
        case .mkdir:
            return !remoteWriteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .delete:
            return selectedEntry != nil
        case .copy, .move:
            return selectedEntry != nil
                && !remoteWriteDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func presentRemoteWrite(_ kind: RemoteWriteKind) {
        remoteWriteKind = kind
        remoteWriteMessage = ""
        remoteWriteName = ""
        if let selectedEntry {
            remoteWriteDestination = join(rootURL, selectedEntry.name + (kind == .copy ? "-copy" : "-moved"))
        } else {
            remoteWriteDestination = rootURL
        }
        showRemoteWriteSheet = true
    }

    private func executeRemoteWrite() async {
        guard let browserVM else { return }
        let message = remoteWriteMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        switch remoteWriteKind {
        case .mkdir:
            await browserVM.createDirectory(named: remoteWriteName, in: rootURL, message: message)
        case .delete:
            guard let selectedEntry else { return }
            await browserVM.delete(entry: selectedEntry, baseURL: rootURL, message: message)
        case .copy:
            guard let selectedEntry else { return }
            await browserVM.copy(
                entry: selectedEntry,
                baseURL: rootURL,
                to: remoteWriteDestination.trimmingCharacters(in: .whitespacesAndNewlines),
                message: message
            )
        case .move:
            guard let selectedEntry else { return }
            await browserVM.move(
                entry: selectedEntry,
                baseURL: rootURL,
                to: remoteWriteDestination.trimmingCharacters(in: .whitespacesAndNewlines),
                message: message
            )
        }
        applyRemoteOperationStatus(browserVM.remoteOperationState)
        if case .completed = browserVM.remoteOperationState {
            showRemoteWriteSheet = false
            selectedEntry = nil
        }
    }

    private func applyRemoteOperationStatus(_ state: RepoRemoteOperationState) {
        switch state {
        case .completed(let op, let revision):
            statusText = "\(label(for: op))成功 r\(revision.value)"
        case .error(let message):
            statusText = "远端写失败：\(message)"
        case .running(let op):
            statusText = "正在\(label(for: op))…"
        case .idle:
            break
        }
    }

    private func label(for op: RepoRemoteOperation) -> String {
        switch op {
        case .mkdir: return "新建目录"
        case .delete: return "删除"
        case .copy: return "复制"
        case .move: return "移动"
        }
    }

    private func bootstrap() async {
        let settings = await session.settingsStore.settings()
        let vm = RepoBrowserViewModel(
            listProvider: session.svnService,
            previewProvider: session.svnService,
            bookmarkManager: session.repoBookmarkStore,
            logProvider: session.svnService,
            remoteOperationProvider: session.svnService,
            logBatchSize: settings.logBatchSize
        )
        browserVM = vm
        checkoutVM = CheckoutViewModel(
            checkoutProvider: session.svnService,
            workspaceImporter: session.workspaceStore,
            infoProvider: session.svnService
        )
        await vm.loadBookmarks()
        if let first = workspaceController.selectedRecord?.repoURL {
            rootURL = first
            await openRoot()
        }
        await consumePendingBrowse()
    }

    /// 消费历史页 L08 注入的仓库 URL（及可选修订）。
    private func consumePendingBrowse() async {
        guard let url = navigator.consumePendingBrowseURL() else { return }
        let rev = navigator.consumePendingBrowseRevision()
        rootURL = url
        if let rev {
            checkoutRevisionText = String(rev.value)
        }
        statusText = rev.map { "来自历史：\(url) @ r\($0.value)" } ?? "来自历史：\(url)"
        await openRoot()
    }

    private func openRoot() async {
        let trimmed = rootURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let browserVM else { return }
        rootURL = trimmed
        await browserVM.loadChildren(of: trimmed)
        switch browserVM.state(for: trimmed) {
        case .loaded:
            statusText = "已加载 \(browserVM.children(of: trimmed).count) 项"
        case .error(let message):
            statusText = "加载失败：\(message)"
        default:
            statusText = nil
        }
    }

    private func previewSelected() async {
        guard let selectedEntry, let browserVM else { return }
        await browserVM.preview(entry: selectedEntry, baseURL: rootURL)
        let url = join(rootURL, selectedEntry.path)
        switch browserVM.previewState(for: url) {
        case .loaded(let text):
            previewText = text
        case .tooLarge(let limit, let actual):
            previewText = "文件过大（\(actual) > \(limit)）"
        case .unsupported(let reason):
            previewText = "无法预览：\(reason)"
        case .error(let message):
            previewText = "预览失败：\(message)"
        default:
            previewText = ""
        }
    }

    private func presentCheckout(for entry: RemoteEntry) {
        let trimmedRev = checkoutRevisionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let revision: Revision?
        if trimmedRev.isEmpty {
            revision = nil
        } else if let value = Int(trimmedRev), value > 0 {
            revision = Revision(value)
        } else {
            statusText = "检出修订号无效：\(trimmedRev)"
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "检出到此目录"
        guard panel.runModal() == .OK, let destination = panel.url, let checkoutVM else { return }
        Task {
            await checkoutVM.checkout(
                entry: entry,
                baseURL: rootURL,
                to: destination.appendingPathComponent(entry.name),
                depth: selectedDepth,
                revision: revision,
                ignoreExternals: checkoutIgnoreExternals
            )
            switch checkoutVM.state {
            case .completed(let record):
                statusText = "检出完成：\(record.localPath)"
                await workspaceController.reload()
                workspaceController.selectedID = record.id
            case .error(let message):
                statusText = "检出失败：\(message)"
            default:
                break
            }
        }
    }

    private func join(_ base: String, _ path: String) -> String {
        base.hasSuffix("/") ? base + path : base + "/" + path
    }
}
