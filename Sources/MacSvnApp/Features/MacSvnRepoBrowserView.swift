import SwiftUI
import MacSvnCore
import AppKit

/// 仓库浏览器：远端目录懒加载、预览、收藏、Checkout 入口。
public struct MacSvnRepoBrowserView: View {
    private let session: MacSvnAppSession
    @ObservedObject private var workspaceController: MacSvnWorkspaceController

    @State private var browserVM: RepoBrowserViewModel?
    @State private var checkoutVM: CheckoutViewModel?
    @State private var rootURL: String = ""
    @State private var selectedEntry: RemoteEntry?
    @State private var selectedDepth: SvnDepth = .infinity
    @State private var statusText: String?
    @State private var previewText: String = ""

    public init(session: MacSvnAppSession, workspaceController: MacSvnWorkspaceController) {
        self.session = session
        self.workspaceController = workspaceController
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
                depth: selectedDepth
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
