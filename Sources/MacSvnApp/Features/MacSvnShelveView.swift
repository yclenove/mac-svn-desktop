import SwiftUI
import MacSvnCore
import AppKit

private enum MacSvnShelfRecordScope: String, CaseIterable, Identifiable {
    case official = "官方 Shelves"
    case local = "本地快照"

    var id: Self { self }
}

private enum MacSvnShelfCreationKind: String, CaseIterable, Identifiable {
    case official = "官方 Shelve"
    case local = "本地搁置"
    case safety = "安全快照"

    var id: Self { self }
}

private enum MacSvnShelfPreviewKind: String, Identifiable {
    case diff = "Diff"
    case log = "Log"
    case patch = "Patch"

    var id: Self { self }
}

private enum MacSvnOfficialShelfDestructiveAction {
    case unshelveAndDrop
    case drop
}

public struct MacSvnShelveView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession

    @State private var paths: [String] = []
    @State private var selected: Set<String> = []
    @State private var viewModel: ShelveViewModel?
    @State private var patchViewModel: PatchViewModel?
    @State private var name = ""
    @State private var statusText: LocalizedStringKey?
    @State private var showCreateShelfSheet = false
    @State private var showPatchSheet = false
    @State private var patchOperation: PatchOperation = .create
    @State private var patchPath = ""
    @State private var message = ""
    @State private var keepLocalChanges = false
    @State private var createSearchText = ""
    @State private var patchSearchText = ""
    @State private var recordScope: MacSvnShelfRecordScope = .official
    @State private var creationKind: MacSvnShelfCreationKind = .official
    @State private var previewKind: MacSvnShelfPreviewKind = .diff
    @State private var selectedShelfID: String?
    @State private var previewText = ""
    @State private var previewErrorText: String?
    @State private var previewRequestID: UUID?
    @State private var previewRunner = MacSvnAuxiliaryLatestRequestRunner()
    @State private var isPreviewLoading = false
    @State private var sheetErrorText: LocalizedStringKey?
    @State private var confirmOfficialDestructiveAction = false
    @State private var pendingOfficialShelf: SvnShelf?
    @State private var pendingOfficialAction: MacSvnOfficialShelfDestructiveAction?
    @State private var confirmLocalDelete = false
    @State private var pendingLocalSnapshot: ShelveSnapshot?
    @State private var confirmMigration = false
    @State private var pendingMigrationSnapshot: ShelveSnapshot?

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
            shelveToolbar
            shelveFeedback

            if workspaceController.selectedRecord == nil {
                ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                shelveWorkspace
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await bootstrap() }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await bootstrap() }
        }
        .onChange(of: navigator.pendingPatchIntent) { _, _ in
            consumePendingPatchIntent()
        }
        .onChange(of: navigator.pendingShelfCreationPaths) { _, _ in
            consumePendingShelfCreation()
        }
        .onChange(of: recordScope) { _, _ in
            synchronizeRecordSelection()
        }
        .onChange(of: selectedShelfID) { _, _ in
            enqueueSelectedPreview()
        }
        .onChange(of: previewKind) { _, _ in
            enqueueSelectedPreview()
        }
        .onDisappear { cancelPreview() }
        .sheet(isPresented: $showCreateShelfSheet) {
            createShelfSheet
                .macSvnDismissibleSheet()
        }
        .sheet(isPresented: $showPatchSheet) {
            patchSheet
                .macSvnDismissibleSheet()
        }
        .confirmationDialog(
            "确认删除官方 shelf？此操作会永久删除 shelf，无法撤销。",
            isPresented: $confirmOfficialDestructiveAction,
            titleVisibility: .visible
        ) {
            Button(officialDestructiveActionTitle, role: .destructive) {
                Task { await runPendingOfficialDestructiveAction() }
            }
            Button("取消", role: .cancel) {
                clearPendingOfficialDestructiveAction()
            }
        }
        .confirmationDialog(
            "确认删除本地快照？此操作无法撤销。",
            isPresented: $confirmLocalDelete,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let snapshot = pendingLocalSnapshot else { return }
                pendingLocalSnapshot = nil
                Task { await deleteLocalSnapshot(snapshot) }
            }
            Button("取消", role: .cancel) {
                pendingLocalSnapshot = nil
            }
        }
        .confirmationDialog(
            "确认迁移到官方 shelf？迁移成功后会删除本地快照，并回滚已迁移的本地改动。",
            isPresented: $confirmMigration,
            titleVisibility: .visible
        ) {
            Button("迁移到官方", role: .destructive) {
                guard let snapshot = pendingMigrationSnapshot else { return }
                pendingMigrationSnapshot = nil
                Task { await migrate(snapshot) }
            }
            Button("取消", role: .cancel) {
                pendingMigrationSnapshot = nil
            }
        }
    }

    private var shelveToolbar: some View {
        HStack(spacing: 8) {
            Label("搁置", systemImage: "archivebox")
                .font(.headline)
            officialAvailabilityView
            Spacer(minLength: 8)
            Button {
                Task { await refreshShelves() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("刷新搁置记录")
            .accessibilityLabel("刷新搁置记录")
            .disabled(isBusy)

            Menu {
                Button("创建 Patch", systemImage: "doc.badge.plus") {
                    presentPatch(.create)
                }
                Button("应用 Patch", systemImage: "square.and.arrow.down") {
                    presentPatch(.apply)
                }
            } label: {
                Label("Patch", systemImage: "doc.zipper")
            }
            .fixedSize()
            .accessibilityIdentifier("shelve.patch.menu")
            .disabled(isBusy)

            Button("新建搁置", systemImage: "archivebox.fill") {
                presentCreateShelf(paths: [])
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("shelve.create.button")
            .disabled(paths.isEmpty || isBusy)
        }
        .padding(.horizontal, 16)
        .frame(height: MacSvnAuxiliaryWorkflowMetrics.toolbarHeight)
        .background(.bar)
    }

    private var shelveFeedback: some View {
        HStack(spacing: 6) {
            if isBusy || isPreviewLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在处理搁置任务")
            }
            if let statusText {
                Image(systemName: (isBusy || isPreviewLoading) ? "clock" : "info.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(statusText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: MacSvnAuxiliaryWorkflowMetrics.feedbackHeight)
        .background(Color.secondary.opacity(0.04))
    }

    private var shelveWorkspace: some View {
        HStack(spacing: 0) {
            shelfRecordList
                .frame(width: MacSvnAuxiliaryWorkflowMetrics.masterWidth)
            Divider()
            shelfDetailPane
                .frame(
                    minWidth: MacSvnAuxiliaryWorkflowMetrics.detailMinimumWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
        }
    }

    private var shelfRecordList: some View {
        VStack(spacing: 0) {
            Picker("记录类型", selection: $recordScope) {
                ForEach(MacSvnShelfRecordScope.allCases) { scope in
                    Text(LocalizedStringKey(scope.rawValue)).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            HStack {
                Text(recordScope == .official
                    ? LocalizedStringKey("官方 Shelves")
                    : LocalizedStringKey("本地快照"))
                    .font(.headline)
                Spacer()
                Text("\(visibleRecordCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)

            Divider()

            if visibleRecordCount == 0 {
                ContentUnavailableView("没有搁置记录",
                    systemImage: "archivebox",
                    description: Text(recordScope == .official
                        ? LocalizedStringKey("还没有官方 shelf")
                        : LocalizedStringKey("还没有本地快照"))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedShelfID) {
                    if recordScope == .official {
                        ForEach(viewModel?.officialShelves ?? []) { shelf in
                            officialShelfRow(shelf)
                                .tag(officialID(for: shelf))
                        }
                    } else {
                        ForEach(viewModel?.snapshots ?? []) { snapshot in
                            localSnapshotRow(snapshot)
                                .tag(localID(for: snapshot))
                        }
                    }
                }
                .listStyle(.inset)
                .disabled(isBusy)
            }
        }
    }

    private func officialShelfRow(_ shelf: SvnShelf) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shelf.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(shelf.name)
            Text("V\(shelf.latestVersion) · \(shelf.pathCount) 个路径")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(shelf.ageSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }

    private func localSnapshotRow(_ snapshot: ShelveSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.name)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(snapshot.name)
            (Text(localKindTitle(snapshot.kind)) + Text(" · \(snapshot.paths.count) 个路径"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var shelfDetailPane: some View {
        if let shelf = selectedOfficialShelf {
            officialShelfDetail(shelf)
        } else if let snapshot = selectedLocalSnapshot {
            localSnapshotDetail(snapshot)
        } else {
            ContentUnavailableView("选择搁置记录",
                systemImage: "archivebox",
                description: Text("从左侧选择记录以查看摘要和预览")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func officialShelfDetail(_ shelf: SvnShelf) -> some View {
        VStack(spacing: 0) {
            shelfDetailHeader(
                title: shelf.name,
                subtitle: "官方 Shelf · V\(shelf.latestVersion)",
                primaryTitle: "Unshelve",
                primarySystemImage: "arrow.uturn.backward",
                primaryAction: { Task { await unshelve(shelf, drop: false) } },
                menu: { officialShelfActions(shelf) }
            )
            shelfSummary {
                LabeledContent("路径数量", value: "\(shelf.pathCount)")
                LabeledContent("最近版本", value: "V\(shelf.latestVersion)")
                LabeledContent("时间", value: shelf.ageSummary)
                if let message = shelf.message, !message.isEmpty {
                    LabeledContent("说明") {
                        Text(message)
                            .lineLimit(2)
                            .textSelection(.enabled)
                            .help(message)
                    }
                }
            }
            Divider()
            shelfPreviewPane
        }
    }

    private func localSnapshotDetail(_ snapshot: ShelveSnapshot) -> some View {
        VStack(spacing: 0) {
            shelfDetailHeader(
                title: snapshot.name,
                subtitle: localKindTitle(snapshot.kind),
                primaryTitle: "恢复",
                primarySystemImage: "arrow.uturn.backward",
                primaryAction: { Task { await restoreLocalSnapshot(snapshot) } },
                menu: { localSnapshotActions(snapshot) }
            )
            shelfSummary {
                LabeledContent("类型") {
                    Text(localKindTitle(snapshot.kind))
                }
                LabeledContent("路径数量", value: "\(snapshot.paths.count)")
                LabeledContent(
                    "创建时间",
                    value: snapshot.createdAt.formatted(date: .abbreviated, time: .shortened)
                )
                LabeledContent("Patch 文件", value: snapshot.patchFileName)
            }
            Divider()
            shelfPreviewPane
        }
    }

    private func shelfDetailHeader<MenuContent: View>(
        title: String,
        subtitle: LocalizedStringKey,
        primaryTitle: LocalizedStringKey,
        primarySystemImage: String,
        primaryAction: @escaping () -> Void,
        @ViewBuilder menu: () -> MenuContent
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(primaryTitle, systemImage: primarySystemImage, action: primaryAction)
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
            Menu(content: menu) {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 28, height: 28)
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .help("更多搁置操作")
            .accessibilityLabel("更多搁置操作")
            .disabled(isBusy)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background(.bar)
    }

    private func shelfSummary<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            content()
        }
        .font(.callout)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func officialShelfActions(_ shelf: SvnShelf) -> some View {
        Button("查看 Diff", systemImage: "doc.text.magnifyingglass") {
            requestPreview(.diff)
        }
        Button("查看 Log", systemImage: "clock.arrow.circlepath") {
            requestPreview(.log)
        }
        Divider()
        Button("Unshelve + Drop", systemImage: "arrow.uturn.backward.circle") {
            requestOfficialDestructiveAction(.unshelveAndDrop, shelf: shelf)
        }
        Button("Drop", systemImage: "trash", role: .destructive) {
            requestOfficialDestructiveAction(.drop, shelf: shelf)
        }
    }

    @ViewBuilder
    private func localSnapshotActions(_ snapshot: ShelveSnapshot) -> some View {
        Button("预览 Patch", systemImage: "doc.text.magnifyingglass") {
            requestPreview(.patch)
        }
        if snapshot.kind == .manual {
            Button("迁移到官方", systemImage: "arrow.up.doc", role: .destructive) {
                pendingMigrationSnapshot = snapshot
                confirmMigration = true
            }
            .disabled(!isOfficialAvailable)
        }
        Divider()
        Button("删除", systemImage: "trash", role: .destructive) {
            pendingLocalSnapshot = snapshot
            confirmLocalDelete = true
        }
    }

    private var shelfPreviewPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("预览")
                    .font(.headline)
                Spacer()
                if selectedOfficialShelf != nil {
                    Picker("预览类型", selection: $previewKind) {
                        Text("Diff").tag(MacSvnShelfPreviewKind.diff)
                        Text("Log").tag(MacSvnShelfPreviewKind.log)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                } else {
                    Label("Patch", systemImage: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 38)

            Divider()

            if previewText.isEmpty {
                if isPreviewLoading {
                    ProgressView("正在加载预览")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let previewErrorText {
                    ContentUnavailableView("预览加载失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(previewErrorText)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("没有预览内容",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("选择记录后将在此显示 Diff、Log 或 Patch")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Text(DiffPerformanceLimits.truncatedDisplayText(previewText))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var createShelfSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("新建搁置")
                    .font(.title2.weight(.semibold))
                Text("选择要保存的变更，并决定使用官方 shelf 或本地快照。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Picker("搁置类型", selection: $creationKind) {
                ForEach(MacSvnShelfCreationKind.allCases) { kind in
                    Text(LocalizedStringKey(kind.rawValue)).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            MacSvnAuxiliaryPathList(
                paths: paths,
                selection: $selected,
                searchText: $createSearchText
            )
            .frame(minHeight: 230)
            .disabled(isBusy)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                TextField("搁置名称", text: $name)
                    .textFieldStyle(.roundedBorder)
                if creationKind == .official {
                    TextField("说明（可选）", text: $message)
                        .textFieldStyle(.roundedBorder)
                    Toggle("保留本地改动", isOn: $keepLocalChanges)
                        .toggleStyle(.checkbox)
                } else if creationKind == .safety {
                    Text("名称留空时将使用 safety。安全快照不会回滚本地改动。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if creationKind == .official, !isOfficialAvailable {
                    Label("当前 SVN 不支持官方 Shelve，请改用本地搁置。", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let sheetErrorText {
                    Label(sheetErrorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                HStack {
                    Text("已选 \(selected.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") { showCreateShelfSheet = false }
                    Button(createShelfActionTitle) {
                        Task { await submitCreateShelf() }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmitCreateShelf || isBusy)
                }
            }
            .padding(20)
        }
        .frame(width: 620, height: 610)
    }

    private var patchSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(patchTitle)
                    .font(.title2.weight(.semibold))
                Text(patchDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            if patchOperation == .create {
                Divider()
                MacSvnAuxiliaryPathList(
                    paths: paths,
                    selection: $selected,
                    searchText: $patchSearchText
                )
                .frame(minHeight: 260)
                .disabled(isPatchBusy)
                Divider()
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField(
                        patchPathPrompt,
                        text: $patchPath
                    )
                    .textFieldStyle(.roundedBorder)
                    Button("选择…") { choosePatchPath() }
                        .disabled(isPatchBusy)
                }
                if patchOperation == .create {
                    Text("当前已选择 \(selected.count) 个变更路径")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let sheetErrorText {
                    Label(sheetErrorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button("取消") { showPatchSheet = false }
                    Button("执行") { Task { await executePatch() } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canExecutePatch || isPatchBusy)
                }
            }
            .padding(20)
        }
        .frame(width: 620, height: patchOperation == .create ? 560 : 220)
    }

    private var canCreateShelf: Bool {
        !selected.isEmpty && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSubmitCreateShelf: Bool {
        switch creationKind {
        case .official:
            return isOfficialAvailable && canCreateShelf
        case .local:
            return canCreateShelf
        case .safety:
            return !selected.isEmpty
        }
    }

    private var createShelfActionTitle: LocalizedStringKey {
        switch creationKind {
        case .official: "创建官方 Shelf"
        case .local: "创建本地搁置"
        case .safety: "创建安全快照"
        }
    }

    private var canExecutePatch: Bool {
        !patchPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (patchOperation != .create || !selected.isEmpty)
    }

    private var patchTitle: LocalizedStringKey {
        patchOperation == .create ? "创建 Patch" : "应用 Patch"
    }

    private var patchDescription: LocalizedStringKey {
        patchOperation == .create
            ? "将所选工作副本变更写入 Patch 文件。"
            : "从 Patch 文件恢复变更到当前工作副本。"
    }

    private var patchPathPrompt: LocalizedStringKey {
        patchOperation == .create ? "输出文件路径" : "Patch 文件路径"
    }

    private var isOfficialAvailable: Bool {
        guard case .available = viewModel?.officialAvailability else { return false }
        return true
    }

    private var isShelveBusy: Bool {
        switch viewModel?.state {
        case .loading, .running:
            return true
        default:
            return false
        }
    }

    private var isPatchBusy: Bool {
        if case .running = patchViewModel?.state { return true }
        return false
    }

    private var isBusy: Bool {
        isShelveBusy || isPatchBusy
    }

    private var visibleRecordCount: Int {
        switch recordScope {
        case .official: viewModel?.officialShelves.count ?? 0
        case .local: viewModel?.snapshots.count ?? 0
        }
    }

    private var selectedOfficialShelf: SvnShelf? {
        guard recordScope == .official, let selectedShelfID else { return nil }
        return viewModel?.officialShelves.first { officialID(for: $0) == selectedShelfID }
    }

    private var selectedLocalSnapshot: ShelveSnapshot? {
        guard recordScope == .local, let selectedShelfID else { return nil }
        return viewModel?.snapshots.first { localID(for: $0) == selectedShelfID }
    }

    @ViewBuilder
    private var officialAvailabilityView: some View {
        switch viewModel?.officialAvailability {
        case .available(let version):
            Label {
                Text(LocalizedStringKey(version.displayName))
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .font(.caption)
            .foregroundStyle(.green)
        case .unavailable(let version, let reason):
            Label {
                Text("\(version.displayName) 不可用：\(reason)")
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(reason)
        case nil:
            ProgressView().controlSize(.small)
        }
    }

    private var officialDestructiveActionTitle: LocalizedStringKey {
        pendingOfficialAction == .unshelveAndDrop ? "Unshelve + Drop" : "Drop"
    }

    private func officialID(for shelf: SvnShelf) -> String {
        "official:\(shelf.id)"
    }

    private func localID(for snapshot: ShelveSnapshot) -> String {
        "local:\(snapshot.id.uuidString)"
    }

    private func localKindTitle(_ kind: ShelveKind) -> LocalizedStringKey {
        switch kind {
        case .manual: "本地搁置"
        case .safety: "安全快照"
        }
    }

    private func presentCreateShelf(paths preselectedPaths: [String]) {
        creationKind = isOfficialAvailable ? .official : .local
        selected = Set(preselectedPaths.filter { paths.contains($0) })
        name = ""
        message = ""
        keepLocalChanges = false
        createSearchText = ""
        sheetErrorText = nil
        showCreateShelfSheet = true
    }

    private func submitCreateShelf() async {
        sheetErrorText = nil
        switch creationKind {
        case .official:
            await createOfficialShelf()
        case .local:
            await createLocalShelf()
        case .safety:
            await createSafetySnapshot()
        }
    }

    private func refreshShelves() async {
        cancelPreview()
        await viewModel?.load()
        synchronizeRecordSelection()
        switch MacSvnShelveFeedbackPresentation.loadOutcome(
            state: viewModel?.state,
            officialError: viewModel?.officialError
        ) {
        case .localFailure(let message):
            statusText = "搁置记录加载失败：\(message)"
        case .officialFailure(let error):
            statusText = "官方 shelf 列表加载失败：\(error)"
        case .refreshed:
            statusText = "已刷新搁置记录"
            enqueueSelectedPreview()
        }
    }

    private func createOfficialShelf() async {
        await viewModel?.officialShelve(
            name: name,
            paths: Array(selected).sorted(),
            message: message,
            keepLocal: keepLocalChanges
        )
        if updateStatus(for: .officialShelve, success: "官方 Shelve 创建完成") {
            showCreateShelfSheet = false
            recordScope = .official
            synchronizeRecordSelection(preferredID: "official:\(name.trimmingCharacters(in: .whitespacesAndNewlines))")
            await reloadPaths()
        }
    }

    private func createLocalShelf() async {
        await viewModel?.shelve(name: name, paths: Array(selected).sorted())
        if updateStatus(for: .shelve, success: "本地搁置创建完成") {
            showCreateShelfSheet = false
            recordScope = .local
            synchronizeRecordSelection()
            await reloadPaths()
        }
    }

    private func createSafetySnapshot() async {
        let snapshotName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        await viewModel?.createSafetySnapshot(
            name: snapshotName.isEmpty ? "safety" : snapshotName,
            paths: Array(selected).sorted()
        )
        if updateStatus(for: .safetySnapshot, success: "安全快照创建完成") {
            showCreateShelfSheet = false
            recordScope = .local
            synchronizeRecordSelection()
        }
    }

    private func unshelve(_ shelf: SvnShelf, drop: Bool) async {
        await viewModel?.officialUnshelve(shelf, drop: drop)
        let suffix = drop ? "并删除 shelf" : ""
        if updateStatus(for: .officialUnshelve, success: "已恢复 \(shelf.name) \(suffix)") {
            synchronizeRecordSelection()
            await reloadPaths()
        }
    }

    private func dropOfficialShelf(_ shelf: SvnShelf) async {
        await viewModel?.officialDrop(shelf)
        if updateStatus(for: .officialDrop, success: "已删除官方 shelf \(shelf.name)") {
            synchronizeRecordSelection()
        }
    }

    private func restoreLocalSnapshot(_ snapshot: ShelveSnapshot) async {
        await viewModel?.restore(snapshot)
        if updateStatus(for: .restore, success: "已恢复 \(snapshot.name)") {
            synchronizeRecordSelection()
            await reloadPaths()
        }
    }

    private func deleteLocalSnapshot(_ snapshot: ShelveSnapshot) async {
        await viewModel?.delete(snapshot)
        if updateStatus(for: .delete, success: "已删除本地快照 \(snapshot.name)") {
            synchronizeRecordSelection()
        }
    }

    private func migrate(_ snapshot: ShelveSnapshot) async {
        await viewModel?.migrateToOfficial(snapshot)
        if updateStatus(for: .migrate, success: "已将 \(snapshot.name) 迁移到官方 shelf") {
            recordScope = .official
            synchronizeRecordSelection()
            await reloadPaths()
        }
    }

    private func requestOfficialDestructiveAction(
        _ action: MacSvnOfficialShelfDestructiveAction,
        shelf: SvnShelf
    ) {
        pendingOfficialShelf = shelf
        pendingOfficialAction = action
        confirmOfficialDestructiveAction = true
    }

    private func runPendingOfficialDestructiveAction() async {
        guard let shelf = pendingOfficialShelf, let action = pendingOfficialAction else { return }
        clearPendingOfficialDestructiveAction()
        switch action {
        case .unshelveAndDrop:
            await unshelve(shelf, drop: true)
        case .drop:
            await dropOfficialShelf(shelf)
        }
    }

    private func clearPendingOfficialDestructiveAction() {
        pendingOfficialShelf = nil
        pendingOfficialAction = nil
    }

    private func requestPreview(_ kind: MacSvnShelfPreviewKind) {
        if previewKind == kind {
            enqueueSelectedPreview()
        } else {
            previewKind = kind
        }
    }

    private func enqueueSelectedPreview() {
        previewRunner.cancel()
        previewText = ""
        previewErrorText = nil

        guard let workingCopyPath = workspaceController.selectedRecord?.localPath else {
            cancelPreview()
            return
        }
        let shelf = selectedOfficialShelf
        let snapshot = selectedLocalSnapshot
        guard shelf != nil || snapshot != nil else {
            cancelPreview()
            return
        }

        let requestedKind = previewKind
        isPreviewLoading = true
        let service = session.shelveService
        let successMessage: LocalizedStringKey
        if let shelf {
            successMessage = requestedKind == .log
                ? "已加载 \(shelf.name) 的版本记录"
                : "已加载 \(shelf.name) 的 Diff"
        } else if let snapshot {
            successMessage = "已加载 \(snapshot.name) 的本地 Patch"
        } else {
            return
        }
        previewRequestID = previewRunner.enqueue(
            operation: {
                if let shelf {
                    let workingCopy = URL(fileURLWithPath: workingCopyPath, isDirectory: true)
                    if requestedKind == .log {
                        return try await service.officialLog(wc: workingCopy, name: shelf.name)
                    }
                    return try await service.officialDiff(
                        wc: workingCopy,
                        name: shelf.name,
                        version: shelf.latestVersion
                    )
                }
                if let snapshot {
                    return try await service.preview(snapshot)
                }
                return ""
            },
            receive: { completedRequestID, result in
                guard MacSvnAuxiliaryLatestRequestPolicy.shouldApply(
                    requestID: completedRequestID,
                    currentRequestID: previewRequestID,
                    isCancelled: false
                ) else { return }
                isPreviewLoading = false
                switch result {
                case .success(let output):
                    previewText = output
                    statusText = successMessage
                case .failure(let error):
                    previewErrorText = error.localizedDescription
                    statusText = "预览加载失败：\(error.localizedDescription)"
                }
            }
        )
    }

    private func cancelPreview() {
        previewRunner.cancel()
        previewRequestID = nil
        isPreviewLoading = false
        previewText = ""
        previewErrorText = nil
    }

    private func synchronizeRecordSelection(preferredID: String? = nil) {
        let availableIDs: [String]
        switch recordScope {
        case .official:
            availableIDs = (viewModel?.officialShelves ?? []).map(officialID)
            previewKind = .diff
        case .local:
            availableIDs = (viewModel?.snapshots ?? []).map(localID)
            previewKind = .patch
        }
        if let preferredID, availableIDs.contains(preferredID) {
            selectedShelfID = preferredID
        } else if let selectedShelfID, availableIDs.contains(selectedShelfID) {
            return
        } else {
            selectedShelfID = availableIDs.first
        }
    }

    @discardableResult
    private func updateStatus(for operation: ShelveOperation, success: LocalizedStringKey) -> Bool {
        switch MacSvnShelveFeedbackPresentation.operationOutcome(
            state: viewModel?.state,
            expected: operation
        ) {
        case .success:
            statusText = success
            return true
        case .failure(let message):
            statusText = "操作失败：\(message)"
            if showCreateShelfSheet {
                sheetErrorText = "操作失败：\(message)"
            }
            return false
        case .pending:
            return false
        }
    }

    private func bootstrap() async {
        cancelPreview()
        selected = []
        selectedShelfID = nil
        statusText = nil
        guard let record = workspaceController.selectedRecord, record.isValid else {
            paths = []
            viewModel = nil
            patchViewModel = nil
            return
        }
        let wc = URL(fileURLWithPath: record.localPath)
        viewModel = ShelveViewModel(workingCopy: wc, shelveProvider: session.shelveService)
        patchViewModel = PatchViewModel(workingCopy: wc, provider: session.svnService)
        await viewModel?.load()
        await reloadPaths()
        if viewModel?.officialShelves.isEmpty == false || viewModel?.snapshots.isEmpty != false {
            recordScope = .official
        } else {
            recordScope = .local
        }
        synchronizeRecordSelection()
        consumePendingPatchIntent()
        consumePendingShelfCreation()
    }

    private func reloadPaths() async {
        guard let record = workspaceController.selectedRecord else { return }
        paths = await MacSvnPathLoader.loadPaths(
            svnService: session.svnService,
            wc: URL(fileURLWithPath: record.localPath)
        )
    }

    private func presentPatch(_ operation: PatchOperation) {
        patchOperation = operation
        patchPath = ""
        patchSearchText = ""
        sheetErrorText = nil
        if operation == .create {
            selected = []
        }
        showPatchSheet = true
    }

    private func choosePatchPath() {
        if patchOperation == .create {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "changes.patch"
            panel.prompt = "创建 Patch"
            if panel.runModal() == .OK, let url = panel.url {
                patchPath = url.path
            }
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.prompt = "应用 Patch"
            if panel.runModal() == .OK, let url = panel.url {
                patchPath = url.path
            }
        }
    }

    private func consumePendingPatchIntent() {
        guard patchViewModel != nil, let intent = navigator.consumePendingPatchIntent() else { return }
        patchOperation = intent.command == .createPatch ? .create : .apply
        if !intent.paths.isEmpty {
            selected = Set(normalizedWorkingCopyPaths(intent.paths))
        }
        patchPath = intent.patchFile ?? ""
        sheetErrorText = nil
        showPatchSheet = true
    }

    private func consumePendingShelfCreation() {
        guard viewModel != nil,
              let pendingPaths = navigator.consumePendingShelfCreationPaths()
        else { return }
        let normalizedPaths = normalizedWorkingCopyPaths(pendingPaths)
        presentCreateShelf(paths: normalizedPaths)
    }

    private func normalizedWorkingCopyPaths(_ pendingPaths: [String]) -> [String] {
        guard let workingCopyPath = workspaceController.selectedRecord?.localPath else {
            return pendingPaths
        }
        let workingCopy = URL(fileURLWithPath: workingCopyPath, isDirectory: true)
        let knownPaths = Set(paths)
        return pendingPaths
            .map { MacSvnAuxiliaryPathPresentation.relativePath($0, workingCopy: workingCopy) }
            .filter(knownPaths.contains)
    }

    private func executePatch() async {
        guard let patchViewModel else { return }
        sheetErrorText = nil
        let file = URL(fileURLWithPath: patchPath.trimmingCharacters(in: .whitespacesAndNewlines))
        switch patchOperation {
        case .create:
            await patchViewModel.create(paths: Array(selected).sorted(), to: file)
        case .apply:
            await patchViewModel.apply(patchFile: file)
        }

        switch patchViewModel.state {
        case .completed(.create):
            statusText = "Patch 创建完成：\(file.path)"
            showPatchSheet = false
        case .completed(.apply):
            statusText = "Patch 应用完成"
            showPatchSheet = false
            await reloadPaths()
        case .error(let message):
            statusText = "Patch 操作失败：\(message)"
            sheetErrorText = "Patch 操作失败：\(message)"
        default:
            break
        }
    }
}
