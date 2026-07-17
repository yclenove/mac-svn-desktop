import SwiftUI
import MacSvnCore

struct ExternalsEditorDraftSnapshot: Equatable {
    let drafts: [ExternalDefinitionDraft]
    let updateAfterSave: Bool
}

enum MacSvnExternalsSaveOutcome: Equatable {
    case failedBeforePropertySave
    case propertySavedUpdateFailed
    case completed
}

enum MacSvnExternalsDraftBaselinePolicy {
    static func baseline(
        initial: ExternalsEditorDraftSnapshot?,
        current: ExternalsEditorDraftSnapshot,
        outcome: MacSvnExternalsSaveOutcome
    ) -> ExternalsEditorDraftSnapshot? {
        switch outcome {
        case .failedBeforePropertySave:
            initial
        case .propertySavedUpdateFailed:
            current
        case .completed:
            nil
        }
    }
}

public struct MacSvnPropertiesView: View {
    @Environment(\.locale) private var locale
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession

    @State private var paths: [String] = ["."]
    @State private var selected: Set<String> = ["."]
    @State private var viewModel: PropertyViewModel?
    @State private var projectProperties = ProjectPropertyPolicy(properties: [])
    @State private var itemInfo: SvnInfo?
    @State private var itemStatus: ItemStatus?
    @State private var infoError: MacSvnAuxiliaryFeedback?
    @State private var loadGeneration = 0
    @State private var name = ""
    @State private var value = ""
    @State private var searchText = ""
    @State private var selectedTemplateName = ""
    @State private var selectedPropertyName: String?
    @State private var loadedTargetPath: String?
    @State private var propertyLoadFeedback: MacSvnAuxiliaryFeedback?
    @State private var feedback: MacSvnAuxiliaryFeedback?
    @State private var pendingDeleteProperty: String?
    @State private var showExternalsEditor = false
    @State private var externalDocument: SvnExternalsDocument?
    @State private var externalDrafts: [ExternalDefinitionDraft] = []
    @State private var updateExternalsAfterSave = true
    @State private var externalFeedback: MacSvnAuxiliaryFeedback?
    @State private var isSavingExternals = false
    @State private var externalsInitialDraft: ExternalsEditorDraftSnapshot?
    @State private var showDiscardExternalsConfirmation = false

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
            propertiesToolbar
            propertiesFeedback

            if workspaceController.selectedRecord == nil {
                ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                propertiesWorkspace
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            updateExternalsAfterSave = session.settingsSnapshot.general.applyLocalExternalsPropertyChanges
            await reloadPaths()
            if navigator.pendingExternalsIntent != nil {
                await consumePendingExternals()
            } else if navigator.pendingPropertyPath != nil {
                await consumePendingProperty()
            } else {
                await loadProperties()
            }
        }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await reloadPaths(); await loadProperties() }
        }
        .onChange(of: navigator.pendingPropertyPath) { _, _ in
            Task { await consumePendingProperty() }
        }
        .onChange(of: navigator.pendingExternalsIntent) { _, _ in
            Task { await consumePendingExternals() }
        }
        .alert(
            "删除属性",
            isPresented: Binding(
                get: { pendingDeleteProperty != nil },
                set: { if !$0 { pendingDeleteProperty = nil } }
            )
        ) {
            Button("取消", role: .cancel) { pendingDeleteProperty = nil }
            Button("删除", role: .destructive) { Task { await deletePendingProperty() } }
        } message: {
            Text("将从当前目标删除属性 \(pendingDeleteProperty ?? "")。")
        }
        .sheet(isPresented: $showExternalsEditor) {
            externalsEditor
                .confirmationDialog(
                    "放弃未保存更改？",
                    isPresented: $showDiscardExternalsConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("放弃更改", role: .destructive) { discardExternalsChanges() }
                    Button("继续编辑", role: .cancel) {}
                }
                .macSvnDismissibleSheet(
                    preventsDismissal: externalsPreventsDismissal,
                    onDismissalBlocked: requestExternalsDismissal
                )
        }
    }

    private var propertiesToolbar: some View {
        HStack(spacing: 8) {
            Label("属性", systemImage: "tag")
                .font(.headline)
            if let target = selected.first {
                Text(MacSvnAuxiliaryPathPresentation.title(for: target))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(target)
            }
            Spacer(minLength: 8)
            Button {
                Task { await loadProperties() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("刷新属性")
            .accessibilityLabel("刷新属性")

            Menu {
                Button("外部定义…", systemImage: "shippingbox") {
                    prepareExternalsEditor()
                }
                .disabled(viewModel == nil || !selectedTargetIsDirectory)
                if projectProperties.initialMessage(for: .propset) != nil {
                    Button("提交属性更改…", systemImage: "checkmark.circle") {
                        openCommitWithPropertyTemplate()
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 28, height: 28)
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .help("更多属性操作")
            .accessibilityLabel("更多属性操作")
        }
        .padding(.horizontal, 16)
        .frame(height: MacSvnAuxiliaryWorkflowMetrics.toolbarHeight)
        .background(.bar)
    }

    private var propertiesFeedback: some View {
        MacSvnInlineFeedbackView(
            feedback: currentPropertiesFeedback,
            truncationMode: .middle
        )
    }

    private var currentPropertiesFeedback: MacSvnAuxiliaryFeedback? {
        switch viewModel?.state {
        case .loading:
            MacSvnAuxiliaryFeedback.localized(
                kind: .progress,
                message: "正在加载属性",
                locale: locale,
                diagnostic: nil
            )
        case .saving:
            MacSvnAuxiliaryFeedback.localized(
                kind: .progress,
                message: "正在保存属性",
                locale: locale,
                diagnostic: nil
            )
        case .deleting:
            MacSvnAuxiliaryFeedback.localized(
                kind: .progress,
                message: "正在删除属性",
                locale: locale,
                diagnostic: nil
            )
        case .error:
            MacSvnPropertyLoadFeedbackPresentation.feedback(
                propertyState: viewModel?.state,
                infoDiagnostic: nil,
                statusDiagnostic: nil,
                projectPropertyDiagnostic: nil,
                locale: locale
            )
        default:
            propertyLoadFeedback ?? feedback
        }
    }

    private var propertiesWorkspace: some View {
        HStack(spacing: 0) {
            propertiesMasterPane
                .frame(width: MacSvnAuxiliaryWorkflowMetrics.masterWidth)
            Divider()
            VStack(spacing: 0) {
                propertyInspector
                Divider()
                propertyList
                Divider()
                propertyEditor
            }
            .frame(
                minWidth: MacSvnAuxiliaryWorkflowMetrics.detailMinimumWidth,
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        }
    }

    private var propertiesMasterPane: some View {
        MacSvnAuxiliaryPathList(
            paths: paths,
            selection: $selected,
            searchText: $searchText,
            allowsMultiple: false
        )
        .onChange(of: selected) { _, _ in
            Task { await loadProperties() }
        }
    }

    private var propertyInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SVN 信息")
                    .font(.headline)
                Spacer()
                Text("属性摘要")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(propertySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    infoLabel("修订")
                    infoValue(itemInfo?.revision.map { "r\($0.value)" } ?? "-")
                    infoLabel("工作副本状态")
                    infoValue(itemStatus?.rawValue ?? "-")
                }
                GridRow {
                    infoLabel("最后作者")
                    infoValue(itemInfo?.lastChangedAuthor ?? "-")
                    infoLabel("锁定")
                    infoValue(lockSummary)
                }
                GridRow {
                    infoLabel("仓库 URL")
                    infoValue(itemInfo?.url ?? "-")
                        .gridCellColumns(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let infoError {
                MacSvnInlineFeedbackView(feedback: infoError)
            }
        }
        .padding(12)
    }

    private func infoLabel(_ label: String) -> some View {
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func infoValue(_ value: String) -> some View {
        Text(value)
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .help(value)
    }

    private var propertyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("属性列表")
                    .font(.headline)
                Spacer()
                Text("\(viewModel?.properties.count ?? 0)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)

            if viewModel?.properties.isEmpty != false {
                ContentUnavailableView("没有属性",
                    systemImage: "tag.slash",
                    description: Text("当前目标没有设置 SVN 属性")
                )
                .frame(maxWidth: .infinity, minHeight: 92, maxHeight: .infinity)
            } else {
                List(selection: $selectedPropertyName) {
                    ForEach(viewModel?.properties ?? [], id: \.name) { property in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(property.name)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text(property.value.replacingOccurrences(of: "\n", with: " "))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(property.value)
                        }
                        .tag(property.name)
                        .contextMenu {
                            Button("删除", role: .destructive) {
                                pendingDeleteProperty = property.name
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .onChange(of: selectedPropertyName) { _, newValue in
                    selectProperty(named: newValue)
                }
            }
        }
        .frame(minHeight: 130, idealHeight: 170, maxHeight: 190)
    }

    private var propertyEditor: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("新增/修改属性")
                        .font(.headline)
                    Picker("模板", selection: $selectedTemplateName) {
                        Text("自定义").tag("")
                        ForEach(availableTemplates, id: \.name) { template in
                            Text(template.name).tag(template.name)
                        }
                    }
                    .onChange(of: selectedTemplateName) { _, newValue in
                        if let template = availableTemplates.first(where: { $0.name == newValue }) {
                            name = template.name
                            value = template.defaultValue
                        }
                    }
                    TextField("名称", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: name) { _, newValue in
                            if !selectedTemplateName.isEmpty, selectedTemplateName != newValue {
                                selectedTemplateName = ""
                            }
                        }
                    Text("值")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $value)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 96, idealHeight: 120)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.25))
                        }
                    ForEach(Array(propertyDraftDiagnostics.enumerated()), id: \.offset) { _, diagnostic in
                        Label(projectPropertyDiagnosticText(diagnostic), systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(12)
            }
            Divider()
            propertyEditorActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var propertyEditorActions: some View {
        HStack {
            if projectProperties.initialMessage(for: .propset) != nil {
                Button("提交属性更改…") {
                    openCommitWithPropertyTemplate()
                }
            }
            Spacer()
            Button("保存") {
                Task { await saveProperty() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(
                viewModel == nil
                    || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private func selectProperty(named propertyName: String?) {
        guard let propertyName,
              let property = viewModel?.properties.first(where: { $0.name == propertyName })
        else { return }
        selectedTemplateName = availableTemplates.contains { $0.name == property.name }
            ? property.name
            : ""
        name = property.name
        value = property.value
    }

    private var lockSummary: String {
        guard let lock = itemInfo?.lock else { return "未锁定" }
        let details = [lock.owner, lock.comment].compactMap { $0 }.filter { !$0.isEmpty }
        return details.isEmpty ? "已锁定" : details.joined(separator: " · ")
    }

    private var propertySummary: String {
        let names = (viewModel?.properties ?? []).map(\.name).sorted()
        return names.isEmpty ? "无" : "\(names.count) 项：\(names.joined(separator: "、"))"
    }

    private var externalsEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("外部定义")
                    .font(.headline)
                Spacer()
                Button("添加", systemImage: "plus") {
                    externalDrafts.append(ExternalDefinitionDraft())
                }
            }
            List {
                ForEach($externalDrafts) { $draft in
                    HStack(spacing: 8) {
                        TextField("-r", text: $draft.revisionText)
                            .frame(width: 54)
                        TextField("文件或目录 URL", text: $draft.url)
                            .frame(minWidth: 240)
                        TextField("peg", text: $draft.pegRevisionText)
                            .frame(width: 54)
                        TextField("本地相对路径", text: $draft.localPath)
                            .frame(minWidth: 150)
                        Button("删除", systemImage: "trash", role: .destructive) {
                            externalDrafts.removeAll { $0.id == draft.id }
                        }
                        .labelStyle(.iconOnly)
                        .help("删除外部定义")
                    }
                }
            }
            .frame(minHeight: 260)
            .dropDestination(for: String.self) { values, _ in
                addDroppedExternalURLs(values)
            }
            .help("拖入仓库 URL 创建外部定义")
            MacSvnInlineFeedbackView(feedback: externalStatusText)
            Toggle("保存后立即更新外部项", isOn: $updateExternalsAfterSave)
            HStack {
                Button("取消") { requestExternalsDismissal() }
                    .disabled(isSavingExternals)
                Spacer()
                if isSavingExternals {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("保存") { Task { await saveExternals() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSavingExternals)
            }
        }
        .padding(20)
        .frame(minWidth: 780, minHeight: 380)
    }

    private var availableTemplates: [SvnPropertyTemplate] {
        let isDirectory = selectedTargetIsDirectory
        return PropertyViewModel.commonTemplates.filter {
            isDirectory ? $0.appliesToDirectory : $0.appliesToFile
        }
    }

    private var propertyDraftDiagnostics: [ProjectPropertyDiagnostic] {
        let propertyName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard propertyName.hasPrefix("bugtraq:") || propertyName.hasPrefix("tsvn:") else { return [] }
        return ProjectPropertyPolicy(properties: [
            SvnProperty(target: selected.first ?? ".", name: propertyName, value: value)
        ]).diagnostics
    }

    private var selectedTargetIsDirectory: Bool {
        guard let record = workspaceController.selectedRecord, let path = selected.first else { return true }
        let target = SvnExternalsPolicy.targetURL(
            workingCopy: URL(fileURLWithPath: record.localPath, isDirectory: true),
            path: path
        )
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private var currentExternalsDraft: ExternalsEditorDraftSnapshot {
        ExternalsEditorDraftSnapshot(
            drafts: externalDrafts,
            updateAfterSave: updateExternalsAfterSave
        )
    }

    private var externalStatusText: MacSvnAuxiliaryFeedback? {
        externalFeedback
    }

    private var hasUnsavedExternalsChanges: Bool {
        guard let externalsInitialDraft else { return false }
        return currentExternalsDraft != externalsInitialDraft
    }

    private var externalsDismissalDecision: MacSvnAuxiliaryDismissalDecision {
        MacSvnAuxiliaryDismissalPolicy.decision(
            isBusy: isSavingExternals,
            isDirty: hasUnsavedExternalsChanges
        )
    }

    private var externalsPreventsDismissal: Bool {
        externalsDismissalDecision.preventsDismissal
    }

    private func reloadPaths() async {
        guard let record = workspaceController.selectedRecord, record.isValid else {
            paths = ["."]; selected = ["."]; return
        }
        var loaded = await MacSvnPathLoader.loadPaths(
            svnService: session.svnService,
            wc: URL(fileURLWithPath: record.localPath)
        )
        if !loaded.contains(".") { loaded.insert(".", at: 0) }
        paths = loaded
    }

    private func loadProperties(preservingFeedback: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if !preservingFeedback {
            feedback = nil
        }
        guard let record = workspaceController.selectedRecord,
              let path = selected.first
        else { return }
        if loadedTargetPath != path {
            loadedTargetPath = path
            selectedPropertyName = nil
            selectedTemplateName = ""
            name = ""
            value = ""
        }
        let vm = PropertyViewModel(
            workingCopy: URL(fileURLWithPath: record.localPath),
            target: path,
            provider: session.svnService
        )
        viewModel = vm
        let workingCopy = URL(fileURLWithPath: record.localPath)
        async let infoRequest = session.svnService.info(
            wc: workingCopy,
            target: path
        )
        async let statusRequest = session.svnService.status(wc: workingCopy)
        await vm.load()
        var loadedProjectProperties = ProjectPropertyPolicy(properties: [])
        var projectPropertyDiagnostic: String?
        do {
            loadedProjectProperties = try await MacSvnProjectPropertyLoader.load(
                svnService: session.svnService,
                workingCopy: workingCopy,
                relativePaths: [path]
            )
        } catch {
            projectPropertyDiagnostic = error.localizedDescription
        }
        var loadedInfo: SvnInfo?
        var infoDiagnostic: String?
        do {
            loadedInfo = try await infoRequest
        } catch {
            infoDiagnostic = error.localizedDescription
        }
        var loadedStatus: ItemStatus?
        var statusDiagnostic: String?
        do {
            let statusTarget = Self.relativeTarget(path, workingCopy: workingCopy)
            loadedStatus = try await statusRequest.first { status in
                status.path == path || status.path == statusTarget
            }?.itemStatus
        } catch {
            loadedStatus = nil
            statusDiagnostic = error.localizedDescription
        }
        guard generation == loadGeneration else { return }
        itemInfo = loadedInfo
        infoError = infoDiagnostic.flatMap { diagnostic in
            MacSvnPropertyLoadFeedbackPresentation.feedback(
                propertyState: .loaded,
                infoDiagnostic: diagnostic,
                statusDiagnostic: nil,
                projectPropertyDiagnostic: nil,
                locale: locale
            )
        }
        itemStatus = loadedStatus
        projectProperties = loadedProjectProperties
        propertyLoadFeedback = MacSvnPropertyLoadFeedbackPresentation.feedback(
            propertyState: vm.state,
            infoDiagnostic: infoDiagnostic,
            statusDiagnostic: statusDiagnostic,
            projectPropertyDiagnostic: projectPropertyDiagnostic,
            locale: locale
        )
    }

    private static func relativeTarget(_ path: String, workingCopy: URL) -> String {
        MacSvnAuxiliaryPathPresentation.relativePath(path, workingCopy: workingCopy)
    }

    private func consumePendingProperty() async {
        guard let path = navigator.consumePendingPropertyPath() else { return }
        let target: String
        if let record = workspaceController.selectedRecord {
            target = MacSvnAuxiliaryPathPresentation.relativePath(
                path,
                workingCopy: URL(fileURLWithPath: record.localPath, isDirectory: true)
            )
        } else {
            target = path
        }
        if !paths.contains(target) {
            paths.insert(target, at: 0)
        }
        selected = [target]
        feedback = MacSvnAuxiliaryFeedback.localized(
            kind: .success,
            message: "来自命令：\(MacSvnAuxiliaryPathPresentation.title(for: target))",
            locale: locale,
            diagnostic: nil
        )
        await loadProperties(preservingFeedback: true)
    }

    private func consumePendingExternals() async {
        guard let intent = navigator.consumePendingExternalsIntent() else { return }
        let rawPath = intent.path ?? "."
        let path: String
        if let record = workspaceController.selectedRecord {
            path = MacSvnAuxiliaryPathPresentation.relativePath(
                rawPath,
                workingCopy: URL(fileURLWithPath: record.localPath, isDirectory: true)
            )
        } else {
            path = rawPath
        }
        if !paths.contains(path) { paths.insert(path, at: 0) }
        selected = [path]
        await loadProperties()
        prepareExternalsEditor()
    }

    private func prepareExternalsEditor() {
        guard selectedTargetIsDirectory else {
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .warning,
                message: "svn:externals 只能设置在版本化目录上",
                locale: locale,
                diagnostic: nil
            )
            return
        }
        let text = viewModel?.properties.first(where: { $0.name == "svn:externals" })?.value ?? ""
        do {
            let document = text.isEmpty
                ? SvnExternalsDocument(definitions: [])
                : try SvnExternalsDocument(text: text)
            externalDocument = document
            externalDrafts = document.definitions.map(ExternalDefinitionDraft.init)
            externalFeedback = nil
            externalsInitialDraft = currentExternalsDraft
            showExternalsEditor = true
        } catch {
            let diagnostic = error.localizedDescription
            let presented = MacSvnAuxiliaryErrorSummaryPresentation.message(diagnostic, locale: locale)
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .failure,
                message: "外部定义读取失败：\(presented)",
                locale: locale,
                diagnostic: diagnostic
            )
        }
    }

    private func saveExternals() async {
        guard !isSavingExternals else { return }
        guard let record = workspaceController.selectedRecord,
              let path = selected.first,
              let viewModel else { return }
        isSavingExternals = true
        externalFeedback = MacSvnAuxiliaryFeedback.localized(
            kind: .progress,
            message: "正在保存外部定义",
            locale: locale,
            diagnostic: nil
        )
        defer { isSavingExternals = false }
        do {
            let definitions = try externalDrafts.map { try $0.definition() }
            if definitions.isEmpty {
                if viewModel.properties.contains(where: { $0.name == "svn:externals" }) {
                    await viewModel.delete(name: "svn:externals")
                }
            } else {
                let base = externalDocument ?? SvnExternalsDocument(definitions: [])
                await viewModel.save(
                    name: "svn:externals",
                    value: base.replacing(definitions: definitions).render()
                )
            }
            guard case .loaded = viewModel.state else {
                if case .error(let message) = viewModel.state {
                    let presented = MacSvnAuxiliaryErrorSummaryPresentation.message(message, locale: locale)
                    externalFeedback = MacSvnAuxiliaryFeedback.localized(
                        kind: .failure,
                        message: "保存失败：\(presented)",
                        locale: locale,
                        diagnostic: message
                    )
                    feedback = externalFeedback
                }
                return
            }
            if updateExternalsAfterSave {
                do {
                    _ = try await session.svnService.update(
                        wc: URL(fileURLWithPath: record.localPath),
                        paths: [path],
                        ignoreExternals: false
                    )
                } catch {
                    let diagnostic = error.localizedDescription
                    let presented = MacSvnAuxiliaryErrorSummaryPresentation.message(diagnostic, locale: locale)
                    externalFeedback = MacSvnAuxiliaryFeedback.localized(
                        kind: .warning,
                        message: "属性已保存，但更新外部项失败：\(presented)",
                        locale: locale,
                        diagnostic: diagnostic
                    )
                    feedback = externalFeedback
                    externalsInitialDraft = MacSvnExternalsDraftBaselinePolicy.baseline(
                        initial: externalsInitialDraft,
                        current: currentExternalsDraft,
                        outcome: .propertySavedUpdateFailed
                    )
                    await loadProperties(preservingFeedback: true)
                    return
                }
            }
            externalsInitialDraft = MacSvnExternalsDraftBaselinePolicy.baseline(
                initial: externalsInitialDraft,
                current: currentExternalsDraft,
                outcome: .completed
            )
            showExternalsEditor = false
            await loadProperties()
            feedback = updateExternalsAfterSave
                ? .localized(kind: .success, message: "已保存并更新外部项", locale: locale, diagnostic: nil)
                : .localized(kind: .success, message: "已保存 svn:externals", locale: locale, diagnostic: nil)
        } catch {
            let diagnostic = error.localizedDescription
            let presented = MacSvnAuxiliaryErrorSummaryPresentation.message(diagnostic, locale: locale)
            externalFeedback = MacSvnAuxiliaryFeedback.localized(
                kind: .failure,
                message: "外部定义操作失败：\(presented)",
                locale: locale,
                diagnostic: diagnostic
            )
            feedback = externalFeedback
        }
    }

    private func requestExternalsDismissal() {
        switch externalsDismissalDecision {
        case .blocked:
            return
        case .confirmDiscard:
            showDiscardExternalsConfirmation = true
        case .dismiss:
            closeExternalsEditor()
        }
    }

    private func discardExternalsChanges() {
        if let externalsInitialDraft {
            externalDrafts = externalsInitialDraft.drafts
            updateExternalsAfterSave = externalsInitialDraft.updateAfterSave
        }
        closeExternalsEditor()
    }

    private func closeExternalsEditor() {
        externalDocument = nil
        externalDrafts = []
        externalFeedback = nil
        externalsInitialDraft = nil
        showDiscardExternalsConfirmation = false
        showExternalsEditor = false
    }

    private func addDroppedExternalURLs(_ values: [String]) -> Bool {
        var added = false
        for value in values {
            let url = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { continue }
            let lastComponent = URL(string: url)?.lastPathComponent
                ?? (url as NSString).lastPathComponent
            externalDrafts.append(ExternalDefinitionDraft(
                url: url,
                localPath: lastComponent.isEmpty ? "external" : lastComponent
            ))
            added = true
        }
        return added
    }

    private func saveProperty() async {
        let propertyName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        await viewModel?.save(name: propertyName, value: value)
        if case .loaded = viewModel?.state {
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .success,
                message: "已保存 \(propertyName)",
                locale: locale,
                diagnostic: nil
            )
        } else if case .error(let message) = viewModel?.state {
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .failure,
                message: "保存失败：\(MacSvnAuxiliaryErrorSummaryPresentation.message(message, locale: locale))",
                locale: locale,
                diagnostic: message
            )
        }
    }

    private func deletePendingProperty() async {
        guard let propertyName = pendingDeleteProperty else { return }
        pendingDeleteProperty = nil
        await viewModel?.delete(name: propertyName)
        if case .loaded = viewModel?.state {
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .success,
                message: "已删除 \(propertyName)",
                locale: locale,
                diagnostic: nil
            )
            if name == propertyName {
                selectedTemplateName = ""
                name = ""
                value = ""
            }
        } else if case .error(let message) = viewModel?.state {
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .failure,
                message: "删除失败：\(MacSvnAuxiliaryErrorSummaryPresentation.message(message, locale: locale))",
                locale: locale,
                diagnostic: message
            )
        }
    }

    private func openCommitWithPropertyTemplate() {
        guard let record = workspaceController.selectedRecord else { return }
        navigator.handle(cli: .commitUI(
            path: record.localPath,
            initialMessage: projectProperties.initialMessage(for: .propset)
        ))
    }

    private func projectPropertyDiagnosticText(_ diagnostic: ProjectPropertyDiagnostic) -> String {
        switch diagnostic {
        case .invalidNonNegativeInteger(let name, let value):
            return "\(name) 需要非负整数：\(value)"
        case .invalidBoolean(let name, let value):
            return "\(name) 需要 true/false：\(value)"
        case .invalidBugtraqRegex(let value):
            return "bugtraq:logregex 无效：\(value)"
        case .invalidBugtraqRegexLineCount(let count):
            return "bugtraq:logregex 需要 1 或 2 行，当前 \(count) 行"
        case .bugtraqMessageMissingPlaceholder:
            return "bugtraq:message 缺少 %BUGID%"
        case .bugtraqRepositoryRootUnavailable:
            return "bugtraq:url 使用 ^/，但无法读取仓库根 URL"
        case .conflictingProjectProperty(let name):
            return "选中路径的 \(name) 配置不一致，已使用保守规则"
        }
    }
}

struct ExternalDefinitionDraft: Identifiable, Equatable {
    let id = UUID()
    var revisionText = ""
    var url = ""
    var pegRevisionText = ""
    var localPath = ""

    init() {}

    init(url: String, localPath: String) {
        self.url = url
        self.localPath = localPath
    }

    init(_ definition: SvnExternalDefinition) {
        revisionText = definition.revision?.description ?? ""
        url = definition.url
        pegRevisionText = definition.pegRevision?.description ?? ""
        localPath = definition.localPath
    }

    func definition() throws -> SvnExternalDefinition {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { throw ExternalDefinitionDraftError.emptyURL }
        return SvnExternalDefinition(
            revision: try parseRevision(revisionText),
            url: trimmedURL,
            pegRevision: try parseRevision(pegRevisionText),
            localPath: try SvnExternalsPolicy.validateLocalPath(localPath)
        )
    }

    private func parseRevision(_ value: String) throws -> Revision? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let number = Int(trimmed), number >= 0 else {
            throw ExternalDefinitionDraftError.invalidRevision(trimmed)
        }
        return Revision(number)
    }
}

private enum ExternalDefinitionDraftError: Error, LocalizedError {
    case emptyURL
    case invalidRevision(String)

    var errorDescription: String? {
        switch self {
        case .emptyURL: "外部定义 URL 不能为空"
        case .invalidRevision(let value): "外部定义修订号无效：\(value)"
        }
    }
}
