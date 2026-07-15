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
            Menu("SVN 操作") {
                ForEach(TransferKind.allCases) { kind in
                    Button(LocalizedStringKey(kind.rawValue)) { presentTransfer(kind) }
                }
                Divider()
                Button("在此创建仓库…") { presentCreateRepository() }
            }
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
            HStack(spacing: 8) {
                Text("名称")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("锁")
                    .frame(width: 150, alignment: .leading)
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
                    guard let path, let browserVM else { return }
                    selectedEntry = browserVM.children(of: rootURL).first(where: { $0.path == path })
                    Task { await previewSelected() }
                }
            )) {
                ForEach(browserVM?.children(of: rootURL) ?? [], id: \.path) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: entry.kind == .directory ? "folder" : "doc")
                        Text(entry.name)
                        Spacer()
                        if let lock = entry.lock {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.orange)
                                Text(lock.owner ?? "已锁定")
                                    .lineLimit(1)
                            }
                            .frame(width: 150, alignment: .leading)
                            .help(lockSummary(lock))
                        } else {
                            Text("")
                                .frame(width: 150)
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
                    .draggable(remoteURL(for: entry))
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
            Button("重命名") { presentRemoteWrite(.rename) }
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
        guard let base = URL(string: rootURL) else {
            return join(rootURL, entry.path)
        }
        return base.appendingPathComponent(entry.path, isDirectory: entry.kind == .directory).absoluteString
    }
}
