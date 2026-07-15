import SwiftUI
import MacSvnCore
import AppKit

/// 仓库浏览器：远端目录懒加载、预览、收藏、Checkout 与远端写操作（mkdir/删/复制/移动）。
public struct MacSvnRepoBrowserView: View {
    @ObservedObject private var session: MacSvnAppSession
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator

    @State private var browserVM: RepoBrowserViewModel?
    @State private var checkoutVM: CheckoutViewModel?
    @State private var rootURL: String = ""
    @State private var selectedEntry: RemoteEntry?
    @State private var showInspectorPopover = false
    @State private var pendingDirectoryURL: String?
    @State private var selectedDepth: SvnDepth = .infinity
    @State private var checkoutRevisionText = ""
    @State private var checkoutIgnoreExternals = false
    @State private var statusText: LocalizedStringKey?
    @State private var previewText: String = ""
    @State private var transferVM: ImportExportViewModel?
    @State private var showTransferSheet = false
    @State private var transferKind: TransferKind = .export
    @State private var transferPath = ""
    @State private var transferURL = ""
    @State private var transferDestination = ""
    @State private var transferFromURL = ""
    @State private var transferToURL = ""
    @State private var transferMessage = ""
    @State private var transferMessageTemplate: String?
    @State private var transferRevision = ""
    @State private var transferIgnoreExternals = false

    /// 远端写操作弹窗状态（均需提交说明，对应 FR-RB-06）。
    @State private var showRemoteWriteSheet = false
    @State private var remoteWriteKind: RemoteWriteKind = .mkdir
    @State private var remoteWriteName = ""
    @State private var remoteWriteDestination = ""
    @State private var remoteWriteMessage = ""
    @State private var remoteWriteMessageTemplate: String?
    @State private var projectProperties = ProjectPropertyPolicy(properties: [])
    @State private var pendingRemoteWriteConfirmation: RepoRemoteWriteConfirmation?
    @State private var showRemoteWriteConfirmation = false
    @State private var createRepositoryVM: CreateRepositoryViewModel?
    @State private var showCreateRepositorySheet = false
    @State private var repositoryPath = ""

    private enum RemoteWriteKind: String, Identifiable {
        case mkdir = "新建目录"
        case delete = "删除"
        case copy = "复制"
        case move = "移动"
        case rename = "重命名"

        var id: String { rawValue }
    }

    private enum TransferKind: String, Identifiable, CaseIterable {
        case export = "导出"
        case importProject = "导入"
        case importInPlace = "就地导入"
        case relocate = "重新定位"
        case removeFromVersionControl = "移除版本控制"
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
        GeometryReader { geometry in
            let widthClass = MacSvnCoreModeWidthClass.resolve(width: geometry.size.width)
            VStack(alignment: .leading, spacing: 0) {
                repositoryToolbar(widthClass: widthClass)
                Divider()
                repositoryWorkspace(width: geometry.size.width)
            }
        }
        .task { await bootstrap() }
        .onChange(of: navigator.pendingBrowseURL) { _, _ in
            Task { await consumePendingBrowse() }
        }
        .onChange(of: navigator.pendingTransferIntent) { _, _ in
            consumePendingTransfer()
        }
        .onChange(of: session.settingsSnapshot.dialogs) { _, dialogs in
            browserVM?.updateSettings(
                preFetchDirectories: dialogs.preFetchRepositoryDirectories,
                showExternals: dialogs.showRepositoryExternals
            )
        }
        .sheet(isPresented: $showRemoteWriteSheet) {
            remoteWriteSheet
                .macSvnDismissibleSheet()
        }
        .sheet(isPresented: $showTransferSheet) {
            transferSheet
                .macSvnDismissibleSheet()
        }
        .sheet(isPresented: $showCreateRepositorySheet) {
            createRepositorySheet
                .macSvnDismissibleSheet()
        }
        .onChange(of: navigator.pendingCreateRepository) { _, pending in
            if pending {
                presentCreateRepository()
            }
        }
        .alert(
            "确认远端操作",
            isPresented: $showRemoteWriteConfirmation,
            presenting: pendingRemoteWriteConfirmation
        ) { confirmation in
            Button("确认", role: .destructive) {
                Task { await confirmRemoteWrite(confirmation) }
            }
            Button("取消", role: .cancel) {
                browserVM?.cancelRemoteOperationConfirmation()
                pendingRemoteWriteConfirmation = nil
            }
        } message: { confirmation in
            Text(remoteWriteConfirmationSummary(confirmation))
        }
    }

    private func repositoryToolbar(widthClass: MacSvnCoreModeWidthClass) -> some View {
        HStack(spacing: 8) {
            Label("仓库浏览", systemImage: "shippingbox")
                .font(.headline)
                .lineLimit(1)
            TextField("仓库 URL", text: $rootURL)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await openRoot() } }
                .frame(minWidth: 180, idealWidth: 420, maxWidth: .infinity)
            Button {
                Task { await openRoot() }
            } label: {
                Image(systemName: "arrow.right.circle")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(browserVM == nil || rootURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("前往仓库 URL")
            .accessibilityLabel("前往仓库 URL")
            Button {
                Task { await openRoot() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
            .disabled(browserVM == nil || rootURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("刷新当前目录")
            .accessibilityLabel("刷新当前目录")
            favoritesMenu
            repositoryOperationsMenu
            if widthClass == .compact {
                Button {
                    showInspectorPopover.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(selectedEntry == nil)
                .help("显示所选条目详情")
                .accessibilityLabel("显示所选条目详情")
                .popover(isPresented: $showInspectorPopover, arrowEdge: .bottom) {
                    detailPane
                        .frame(width: 400, height: 560)
                        .macSvnDismissiblePopover()
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: MacSvnCoreModeMetrics.toolbarHeight)
    }

    private var favoritesMenu: some View {
        Menu {
            Button("收藏当前 URL", systemImage: "star") {
                Task { await browserVM?.addBookmark(url: rootURL) }
            }
            .disabled(browserVM == nil || rootURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let bookmarks = browserVM?.bookmarks, !bookmarks.isEmpty {
                Divider()
                Section("收藏") {
                    ForEach(bookmarks) { bookmark in
                        Button(bookmark.name) {
                            rootURL = bookmark.url
                            Task { await openRoot() }
                        }
                    }
                }
                Menu("移除收藏", systemImage: "star.slash") {
                    ForEach(bookmarks) { bookmark in
                        Button(bookmark.name, role: .destructive) {
                            Task { await browserVM?.removeBookmark(id: bookmark.id) }
                        }
                    }
                }
            }
        } label: {
            Label("仓库收藏", systemImage: "star")
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("仓库收藏")
        .accessibilityLabel("仓库收藏")
    }

    private var repositoryOperationsMenu: some View {
        Menu {
            ForEach(TransferKind.allCases) { kind in
                Button(LocalizedStringKey(kind.rawValue)) { presentTransfer(kind) }
            }
            Divider()
            Button("在此创建仓库…") { presentCreateRepository() }
        } label: {
            Label("仓库操作", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("仓库操作")
        .accessibilityLabel("仓库操作")
    }

    @ViewBuilder
    private func repositoryWorkspace(width: CGFloat) -> some View {
        let widthClass = MacSvnCoreModeWidthClass.resolve(width: width)
        HStack(spacing: 0) {
            centerPane
                .frame(minWidth: MacSvnCoreModeMetrics.masterMinimumWidth)
            if widthClass == .regular {
                Divider()
                detailPane
                    .frame(minWidth: MacSvnCoreModeMetrics.inspectorMinimumWidth)
            }
        }
    }

    private var centerPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            remoteWriteToolbar
            repositoryStatusBar
            HStack(spacing: 8) {
                Text("名称")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("锁")
                    .frame(width: 110, alignment: .leading)
                Text("修订")
                    .frame(width: 56, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            List(selection: Binding(
                get: { selectedEntry?.path },
                set: { path in
                    guard let browserVM else { return }
                    let entry = path.flatMap { selectedPath in
                        browserVM.children(of: rootURL).first(where: { $0.path == selectedPath })
                    }
                    selectedEntry = entry
                    guard let entry, entry.kind == .file else {
                        previewText = ""
                        return
                    }
                    previewText = "正在加载预览…"
                    Task { await previewSelected() }
                }
            )) {
                ForEach(browserVM?.children(of: rootURL) ?? [], id: \.path) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: entry.kind == .directory ? "folder" : "doc")
                        Text(entry.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(entry.name)
                        Spacer()
                        if let lock = entry.lock {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.orange)
                                Text(lock.owner ?? "已锁定")
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(width: 110, alignment: .leading)
                            .help(lockSummary(lock))
                        } else {
                            Text("")
                                .frame(width: 110)
                        }
                        if let revision = entry.revision {
                            Text("r\(revision.value)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 56, alignment: .trailing)
                        } else {
                            Text("")
                                .frame(width: 56)
                        }
                    }
                    .tag(entry.path)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        Task { await openDirectory(entry) }
                    }
                    .draggable(remoteURL(for: entry))
                }
            }
            .overlay {
                if let browserVM,
                   browserVM.state(for: rootURL) == .loaded,
                   browserVM.children(of: rootURL).isEmpty {
                    ContentUnavailableView("目录为空", systemImage: "folder")
                }
            }
            .onKeyPress(.return) {
                guard let selectedEntry, selectedEntry.kind == .directory else {
                    return .ignored
                }
                Task { await openDirectory(selectedEntry) }
                return .handled
            }
        }
    }

    @ViewBuilder
    private var repositoryStatusBar: some View {
        HStack(spacing: 8) {
            if let browserVM {
                switch browserVM.state(for: rootURL) {
                case .loading:
                    ProgressView()
                        .controlSize(.small)
                    Text("正在加载目录…")
                case .error(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .foregroundStyle(.red)
                case .idle, .loaded:
                    if let statusText {
                        Text(statusText)
                    } else {
                        Text(" ")
                            .accessibilityHidden(true)
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("正在准备仓库浏览器…")
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(minHeight: 28)
    }

    private var remoteWriteToolbar: some View {
        HStack(spacing: 8) {
            Button {
                presentRemoteWrite(.mkdir)
            } label: {
                Label("新建目录", systemImage: "folder.badge.plus")
            }
            .disabled(browserVM == nil || rootURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            selectedEntryActionsMenu
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var selectedEntryActionsMenu: some View {
        Menu {
            Button("删除", systemImage: "trash", role: .destructive) {
                presentRemoteWrite(.delete)
            }
            Button("复制", systemImage: "doc.on.doc") {
                presentRemoteWrite(.copy)
            }
            Button("移动", systemImage: "arrow.right.square") {
                presentRemoteWrite(.move)
            }
            Button("重命名", systemImage: "pencil") {
                presentRemoteWrite(.rename)
            }
        } label: {
            Label("所选条目操作", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(selectedEntry == nil)
        .help("所选条目操作")
        .accessibilityLabel("所选条目操作")
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("详情")
                        .font(.headline)
                    Spacer()
                    if let selectedEntry, selectedEntry.kind == .directory {
                        Button {
                            Task { await openDirectory(selectedEntry) }
                        } label: {
                            Label("打开目录", systemImage: "folder")
                        }
                    }
                }
                if let selectedEntry {
                    LabeledContent("名称", value: selectedEntry.name)
                    LabeledContent("类型") {
                        Text(remoteEntryKindLabel(selectedEntry.kind))
                    }
                    LabeledContent("远端 URL") {
                        Text(remoteURL(for: selectedEntry))
                            .font(.caption.monospaced())
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(remoteURL(for: selectedEntry))
                    }
                    if let revision = selectedEntry.revision {
                        LabeledContent("修订", value: "r\(revision.value)")
                    }
                    if let author = selectedEntry.author {
                        LabeledContent("作者", value: author)
                    }
                    if let lock = selectedEntry.lock {
                        Divider()
                        LabeledContent("锁持有者", value: lock.owner ?? "未知")
                        if let comment = lock.comment, !comment.isEmpty {
                            LabeledContent("锁说明", value: comment)
                        }
                        if let created = lock.created {
                            LabeledContent("锁定时间") {
                                Text(created, format: .dateTime.year().month().day().hour().minute())
                            }
                        }
                    }

                    Divider()
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
                    .disabled(selectedEntry.kind != .directory)

                    Divider()
                    Text("内容预览")
                        .font(.headline)
                    if selectedEntry.kind == .directory {
                        Text("目录无需预览；双击列表行或使用“打开目录”进入。")
                            .foregroundStyle(.secondary)
                    } else if selectedEntry.kind == .file {
                        Text(previewText.isEmpty ? "选择文件可预览内容" : previewText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color.secondary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Text("此远端条目类型不支持内容预览。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ContentUnavailableView(
                        "未选择远端条目",
                        systemImage: "shippingbox",
                        description: Text("从目录列表选择文件或目录查看详情")
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private var remoteWriteSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedStringKey(remoteWriteKind.rawValue))
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
            case .rename:
                if let selectedEntry {
                    LabeledContent("原名称", value: selectedEntry.name)
                }
                TextField("新名称", text: $remoteWriteName)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("提交说明（必填）", text: $remoteWriteMessage)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("取消") { showRemoteWriteSheet = false }
                Button(requiresRemoteWriteConfirmation ? "继续" : "执行并提交") {
                    Task { await executeRemoteWrite() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmitRemoteWrite)
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }

    private var transferSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LocalizedStringKey(transferKind.rawValue)).font(.title2.weight(.semibold))
            Picker("操作", selection: $transferKind) {
                ForEach(TransferKind.allCases) { kind in
                    Text(LocalizedStringKey(kind.rawValue)).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: transferKind) { _, _ in applyTransferMessageTemplate() }

            switch transferKind {
            case .export:
                TextField("仓库 URL", text: $transferURL).textFieldStyle(.roundedBorder)
                TextField("导出到本地路径", text: $transferDestination).textFieldStyle(.roundedBorder)
                TextField("修订（留空=HEAD）", text: $transferRevision).textFieldStyle(.roundedBorder)
                Toggle("忽略外部项", isOn: $transferIgnoreExternals)
            case .importProject, .importInPlace:
                TextField("本地目录", text: $transferPath).textFieldStyle(.roundedBorder)
                TextField("仓库 URL", text: $transferURL).textFieldStyle(.roundedBorder)
                TextField("提交说明（必填）", text: $transferMessage).textFieldStyle(.roundedBorder)
            case .relocate:
                TextField("From URL", text: $transferFromURL).textFieldStyle(.roundedBorder)
                TextField("To URL", text: $transferToURL).textFieldStyle(.roundedBorder)
                LabeledContent("工作副本", value: workspaceController.selectedRecord?.localPath ?? "未选择")
            case .removeFromVersionControl:
                TextField("本地目录", text: $transferPath).textFieldStyle(.roundedBorder)
                Text("只删除 .svn 元数据，保留工作文件。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if case .completed(let message) = transferVM?.state {
                Text(message).foregroundStyle(.green)
            } else if case .error(let message) = transferVM?.state {
                Text(message).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("取消") { showTransferSheet = false }
                Button("执行") { Task { await executeTransfer() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canExecuteTransfer)
            }
        }
        .padding(24)
        .frame(minWidth: 520)
    }

    private var createRepositorySheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("在此创建仓库").font(.title2.weight(.semibold))
            HStack {
                TextField("仓库目录", text: $repositoryPath)
                    .textFieldStyle(.roundedBorder)
                Button("选择…") { chooseRepositoryPath() }
            }
            LabeledContent("文件系统", value: "FSFS")
            if case .error(let message) = createRepositoryVM?.state {
                Text(message).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("取消") { showCreateRepositorySheet = false }
                Button("创建") { Task { await createRepository() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(repositoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 500)
    }

    private func presentCreateRepository() {
        _ = navigator.consumePendingCreateRepository()
        createRepositoryVM = CreateRepositoryViewModel(provider: session.repositoryCreator)
        repositoryPath = ""
        showCreateRepositorySheet = true
    }

    private func chooseRepositoryPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择仓库目录"
        if panel.runModal() == .OK, let url = panel.url {
            repositoryPath = url.path
        }
    }

    private func createRepository() async {
        guard let createRepositoryVM else { return }
        await createRepositoryVM.create(path: repositoryPath)
        switch createRepositoryVM.state {
        case .completed(let destination):
            statusText = "仓库创建完成：\(destination.path)"
            rootURL = destination.absoluteString
            showCreateRepositorySheet = false
            await openRoot()
        case .error(let message):
            statusText = "创建仓库失败：\(message)"
        default:
            break
        }
    }

    private var canExecuteTransfer: Bool {
        switch transferKind {
        case .export: return !transferURL.isEmpty && !transferDestination.isEmpty
        case .importProject, .importInPlace: return !transferPath.isEmpty && !transferURL.isEmpty && !transferMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .relocate: return !transferFromURL.isEmpty && !transferToURL.isEmpty && workspaceController.selectedRecord != nil
        case .removeFromVersionControl: return !transferPath.isEmpty
        }
    }

    private func presentTransfer(_ kind: TransferKind) {
        transferKind = kind
        transferVM = ImportExportViewModel(provider: session.svnService)
        createRepositoryVM = CreateRepositoryViewModel(provider: session.repositoryCreator)
        transferPath = workspaceController.selectedRecord?.localPath ?? ""
        transferURL = rootURL
        transferDestination = ""
        transferFromURL = ""
        transferToURL = ""
        transferMessage = ""
        transferMessageTemplate = nil
        transferRevision = ""
        applyTransferMessageTemplate()
        showTransferSheet = true
    }

    private func consumePendingTransfer() {
        guard let intent = navigator.consumePendingTransferIntent() else { return }
        if intent.command == .checkout, let url = intent.url,
           let parsedURL = URL(string: url) {
            let name = parsedURL.lastPathComponent
            guard !name.isEmpty else { return }
            rootURL = parsedURL.deletingLastPathComponent().absoluteString
            if let revision = intent.revision {
                checkoutRevisionText = String(revision.value)
            }
            let entry = RemoteEntry(
                name: name,
                path: name,
                kind: .directory,
                size: nil,
                revision: intent.revision,
                author: nil,
                date: nil
            )
            selectedEntry = entry
            presentCheckout(for: entry)
            return
        }
        switch intent.command {
        case .export: transferKind = .export
        case .importToRepository: transferKind = .importProject
        case .importInPlace: transferKind = .importInPlace
        case .relocate: transferKind = .relocate
        case .removeFromVersionControl: transferKind = .removeFromVersionControl
        default: return
        }
        transferVM = ImportExportViewModel(provider: session.svnService)
        transferPath = intent.path ?? workspaceController.selectedRecord?.localPath ?? ""
        transferURL = intent.url ?? rootURL
        transferMessage = intent.message ?? ""
        transferMessageTemplate = nil
        applyTransferMessageTemplate()
        if let revision = intent.revision { transferRevision = String(revision.value) }
        showTransferSheet = true
    }

    private func executeTransfer() async {
        guard let transferVM else { return }
        switch transferKind {
        case .export:
            let revision = Int(transferRevision).map { Revision($0) }
            await transferVM.export(url: transferURL, to: URL(fileURLWithPath: transferDestination), revision: revision, ignoreExternals: transferIgnoreExternals)
        case .importProject:
            await transferVM.importProject(path: URL(fileURLWithPath: transferPath), url: transferURL, message: transferMessage)
        case .importInPlace:
            await transferVM.importInPlace(path: URL(fileURLWithPath: transferPath), url: transferURL, message: transferMessage)
        case .relocate:
            guard let wc = workspaceController.selectedRecord?.localPath else { return }
            await transferVM.relocate(wc: URL(fileURLWithPath: wc), from: transferFromURL, to: transferToURL)
        case .removeFromVersionControl:
            await transferVM.removeFromVersionControl(path: URL(fileURLWithPath: transferPath))
        }
        if case .completed(let message) = transferVM.state {
            statusText = LocalizedStringKey(message)
        }
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
        case .rename:
            return selectedEntry != nil
                && !remoteWriteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var requiresRemoteWriteConfirmation: Bool {
        switch remoteWriteKind {
        case .delete, .move, .rename:
            return true
        case .mkdir, .copy:
            return false
        }
    }

    private func presentRemoteWrite(_ kind: RemoteWriteKind) {
        remoteWriteKind = kind
        remoteWriteMessage = ""
        remoteWriteMessageTemplate = nil
        applyRemoteWriteMessageTemplate()
        remoteWriteName = kind == .rename ? selectedEntry?.name ?? "" : ""
        pendingRemoteWriteConfirmation = nil
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
            await browserVM.delete(
                entry: selectedEntry,
                baseURL: rootURL,
                message: message
            )
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
        case .rename:
            guard let selectedEntry else { return }
            await browserVM.rename(
                entry: selectedEntry,
                baseURL: rootURL,
                to: remoteWriteName,
                message: message
            )
        }
        if case .confirmationRequired(let confirmation) = browserVM.remoteOperationState {
            pendingRemoteWriteConfirmation = confirmation
            showRemoteWriteConfirmation = true
            return
        }
        applyRemoteOperationStatus(browserVM.remoteOperationState)
        if case .completed = browserVM.remoteOperationState {
            showRemoteWriteSheet = false
            selectedEntry = nil
            pendingRemoteWriteConfirmation = nil
        }
    }

    private func confirmRemoteWrite(_ confirmation: RepoRemoteWriteConfirmation) async {
        guard let browserVM else { return }
        await browserVM.confirmRemoteOperation(confirmation)
        applyRemoteOperationStatus(browserVM.remoteOperationState)
        if case .completed = browserVM.remoteOperationState {
            showRemoteWriteConfirmation = false
            showRemoteWriteSheet = false
            selectedEntry = nil
            pendingRemoteWriteConfirmation = nil
        }
    }

    private func applyRemoteOperationStatus(_ state: RepoRemoteOperationState) {
        switch state {
        case .completed(let op, let revision):
            statusText = "\(label(for: op))成功 r\(revision.value)"
        case .error(let message):
            statusText = "远端写失败：\(message)"
        case .confirmationRequired:
            statusText = "等待确认远端\(remoteWriteKind.rawValue)"
        case .running(let op):
            statusText = "正在\(label(for: op))…"
        case .idle:
            break
        }
    }

    private func applyTransferMessageTemplate() {
        guard transferMessage.isEmpty || transferMessage == transferMessageTemplate else { return }
        guard transferKind == .importProject || transferKind == .importInPlace else { return }
        let template = projectProperties.initialMessage(for: .import)
        transferMessageTemplate = template
        transferMessage = template ?? ""
    }

    private func applyRemoteWriteMessageTemplate() {
        guard remoteWriteMessage.isEmpty || remoteWriteMessage == remoteWriteMessageTemplate else { return }
        let operation: ProjectLogTemplateOperation
        switch remoteWriteKind {
        case .mkdir:
            operation = .mkdir
        case .delete:
            operation = .delete
        case .copy:
            operation = .branch
        case .move, .rename:
            operation = .move
        }
        let template = projectProperties.initialMessage(for: operation)
        remoteWriteMessageTemplate = template
        remoteWriteMessage = template ?? ""
    }

    private func label(for op: RepoRemoteOperation) -> String {
        switch op {
        case .mkdir: return "新建目录"
        case .delete: return "删除"
        case .copy: return "复制"
        case .move: return "移动"
        case .rename: return "重命名"
        }
    }

    private func remoteWriteConfirmationSummary(_ confirmation: RepoRemoteWriteConfirmation) -> String {
        if let destination = confirmation.destinationURL {
            return "源：\(confirmation.sourceURL)\n目标：\(destination)\n确认后将立即提交到仓库。"
        }
        return "目标：\(confirmation.sourceURL)\n确认后将立即提交到仓库，且不能通过工作副本撤销。"
    }

    private func lockSummary(_ lock: RemoteLockInfo) -> String {
        var parts = ["持有者：\(lock.owner ?? "未知")"]
        if let comment = lock.comment, !comment.isEmpty {
            parts.append("说明：\(comment)")
        }
        if let created = lock.created {
            parts.append("时间：\(created.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.joined(separator: "\n")
    }

    private func remoteEntryKindLabel(_ kind: RemoteEntryKind) -> LocalizedStringKey {
        switch kind {
        case .file:
            return "文件"
        case .directory:
            return "目录"
        case .unknown:
            return "未知类型"
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
            logBatchSize: settings.logBatchSize,
            preFetchDirectories: settings.dialogs.preFetchRepositoryDirectories,
            showExternals: settings.dialogs.showRepositoryExternals
        )
        browserVM = vm
        checkoutVM = CheckoutViewModel(
            checkoutProvider: session.svnService,
            workspaceImporter: session.workspaceStore,
            infoProvider: session.svnService
        )
        transferVM = ImportExportViewModel(provider: session.svnService)
        if let record = workspaceController.selectedRecord, record.isValid {
            let workingCopy = URL(fileURLWithPath: record.localPath)
            projectProperties = (try? await MacSvnProjectPropertyLoader.load(
                svnService: session.svnService,
                workingCopy: workingCopy,
                relativePaths: ["."]
            )) ?? ProjectPropertyPolicy(properties: [])
        }
        await vm.loadBookmarks()
        if let first = workspaceController.selectedRecord?.repoURL {
            rootURL = first
            await openRoot()
        } else if !settings.dialogs.defaultCheckoutURL.isEmpty {
            rootURL = settings.dialogs.defaultCheckoutURL
        }
        await consumePendingBrowse()
        consumePendingTransfer()
        if navigator.pendingCreateRepository {
            presentCreateRepository()
        }
    }

    /// 消费历史页 L08 注入的仓库 URL（及可选修订）。
    ///
    /// 列表仍按 URL 浏览；修订写入检出表单，提示用户当前为历史 peg（完整 peg list 属 Repo Browser 进阶）。
    private func consumePendingBrowse() async {
        guard let url = navigator.consumePendingBrowseURL() else { return }
        let rev = navigator.consumePendingBrowseRevision()
        rootURL = url
        if let rev {
            checkoutRevisionText = String(rev.value)
            statusText = "来自历史：\(url) @ r\(rev.value)（目录列表为当前 HEAD；检出请用下方修订）"
        } else {
            statusText = "来自历史：\(url)"
        }
        await openRoot()
    }

    private func openRoot() async {
        let trimmed = rootURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let browserVM else { return }
        pendingDirectoryURL = nil
        let selectedPath = selectedEntry?.path
        rootURL = trimmed
        previewText = ""
        await browserVM.loadChildren(of: trimmed)
        guard rootURL.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
        switch browserVM.state(for: trimmed) {
        case .loaded:
            let children = browserVM.children(of: trimmed)
            selectedEntry = selectedPath.flatMap { path in
                children.first(where: { $0.path == path })
            }
            statusText = "已加载 \(children.count) 项"
            if selectedEntry?.kind == .file {
                previewText = "正在加载预览…"
                await previewSelected()
            }
        case .error(let message):
            statusText = "加载失败：\(message)"
        default:
            statusText = nil
        }
    }

    private func openDirectory(_ entry: RemoteEntry) async {
        guard entry.kind == .directory, let browserVM else { return }
        let parentURL = rootURL
        let childURL = remoteURL(baseURL: parentURL, for: entry)
        pendingDirectoryURL = childURL
        await browserVM.loadChildren(of: childURL)
        guard pendingDirectoryURL == childURL, rootURL == parentURL else { return }
        pendingDirectoryURL = nil
        switch browserVM.state(for: childURL) {
        case .loaded:
            rootURL = childURL
            selectedEntry = nil
            previewText = ""
            showInspectorPopover = false
            statusText = "已加载 \(browserVM.children(of: childURL).count) 项"
        case .error(let message):
            statusText = "加载失败：\(message)"
        default:
            break
        }
    }

    private func previewSelected() async {
        guard let entry = selectedEntry, let browserVM else { return }
        let baseURL = rootURL
        let previewURL = remoteURL(baseURL: baseURL, for: entry)
        await browserVM.preview(entry: entry, baseURL: baseURL)
        guard rootURL == baseURL, selectedEntry?.path == entry.path else { return }
        switch browserVM.previewState(for: previewURL) {
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
        let defaultPath = session.settingsSnapshot.dialogs.defaultCheckoutPath
        if !defaultPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: defaultPath, isDirectory: true)
        }
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

    private func remoteURL(for entry: RemoteEntry) -> String {
        remoteURL(baseURL: rootURL, for: entry)
    }

    private func remoteURL(baseURL: String, for entry: RemoteEntry) -> String {
        guard let base = URL(string: baseURL) else {
            return join(baseURL, entry.path)
        }
        return base.appendingPathComponent(entry.path, isDirectory: entry.kind == .directory).absoluteString
    }
}
