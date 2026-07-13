import SwiftUI
import MacSvnCore

public struct MacSvnPropertiesView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession

    @State private var paths: [String] = ["."]
    @State private var selected: Set<String> = ["."]
    @State private var viewModel: PropertyViewModel?
    @State private var name = ""
    @State private var value = ""
    @State private var statusText: String?
    @State private var pendingDeleteProperty: String?
    @State private var showExternalsEditor = false
    @State private var externalDocument: SvnExternalsDocument?
    @State private var externalDrafts: [ExternalDefinitionDraft] = []
    @State private var updateExternalsAfterSave = true
    @State private var externalStatusText: String?
    @State private var isSavingExternals = false

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
            HStack {
                Text("属性")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                Button("外部定义…", systemImage: "shippingbox") {
                    prepareExternalsEditor()
                }
                .disabled(viewModel == nil || !selectedTargetIsDirectory)
                Button("刷新") { Task { await loadProperties() } }
            }
            .padding(24)

            if workspaceController.selectedRecord == nil {
                ContentUnavailableView("未选择工作副本", systemImage: "externaldrive")
            } else {
                HSplitView {
                    MacSvnPathPicker(paths: paths, selection: $selected, allowsMultiple: false)
                        .frame(minWidth: 200)
                        .onChange(of: selected) { _, _ in
                            Task { await loadProperties() }
                        }
                    VStack(alignment: .leading, spacing: 12) {
                        if let statusText { Text(statusText).font(.caption).foregroundStyle(.secondary) }
                        List(viewModel?.properties ?? [], id: \.name) { prop in
                            VStack(alignment: .leading) {
                                Text(prop.name).font(.headline)
                                Text(prop.value).font(.caption.monospaced())
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                name = prop.name
                                value = prop.value
                            }
                            .contextMenu {
                                Button("删除", role: .destructive) {
                                    pendingDeleteProperty = prop.name
                                }
                            }
                        }
                        Form {
                            Section("新增/修改") {
                                Picker("模板", selection: $name) {
                                    Text("自定义").tag("")
                                    ForEach(availableTemplates, id: \.name) { template in
                                        Text(template.name).tag(template.name)
                                    }
                                }
                                .onChange(of: name) { _, newValue in
                                    if let template = availableTemplates.first(where: { $0.name == newValue }) {
                                        value = template.defaultValue
                                    }
                                }
                                TextField("名称", text: $name)
                                TextEditor(text: $value)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(minHeight: 90, maxHeight: 180)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.secondary.opacity(0.25))
                                    }
                                Button("保存") {
                                    Task { await saveProperty() }
                                }
                                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .formStyle(.grouped)
                    }
                    .frame(minWidth: 360)
                }
            }
        }
        .task {
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
        }
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
            if let externalStatusText {
                Text(externalStatusText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Toggle("保存后立即更新外部项", isOn: $updateExternalsAfterSave)
            HStack {
                Button("取消") { showExternalsEditor = false }
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

    private var selectedTargetIsDirectory: Bool {
        guard let record = workspaceController.selectedRecord, let path = selected.first else { return true }
        let target = SvnExternalsPolicy.targetURL(
            workingCopy: URL(fileURLWithPath: record.localPath, isDirectory: true),
            path: path
        )
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory) && isDirectory.boolValue
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

    private func loadProperties() async {
        guard let record = workspaceController.selectedRecord,
              let path = selected.first
        else { return }
        let vm = PropertyViewModel(
            workingCopy: URL(fileURLWithPath: record.localPath),
            target: path,
            provider: session.svnService
        )
        viewModel = vm
        await vm.load()
    }

    private func consumePendingProperty() async {
        guard let path = navigator.consumePendingPropertyPath() else { return }
        if !paths.contains(path) {
            paths.insert(path, at: 0)
        }
        selected = [path]
        statusText = "来自命令：\(path)"
        await loadProperties()
    }

    private func consumePendingExternals() async {
        guard let intent = navigator.consumePendingExternalsIntent() else { return }
        let path = intent.path ?? "."
        if !paths.contains(path) { paths.insert(path, at: 0) }
        selected = [path]
        await loadProperties()
        prepareExternalsEditor()
    }

    private func prepareExternalsEditor() {
        guard selectedTargetIsDirectory else {
            statusText = "svn:externals 只能设置在版本化目录上"
            return
        }
        let text = viewModel?.properties.first(where: { $0.name == "svn:externals" })?.value ?? ""
        do {
            let document = text.isEmpty
                ? SvnExternalsDocument(definitions: [])
                : try SvnExternalsDocument(text: text)
            externalDocument = document
            externalDrafts = document.definitions.map(ExternalDefinitionDraft.init)
            externalStatusText = nil
            showExternalsEditor = true
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func saveExternals() async {
        guard !isSavingExternals else { return }
        guard let record = workspaceController.selectedRecord,
              let path = selected.first,
              let viewModel else { return }
        isSavingExternals = true
        externalStatusText = nil
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
                    externalStatusText = "保存失败：\(message)"
                    statusText = externalStatusText
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
                    externalStatusText = "属性已保存，但更新外部项失败：\(error.localizedDescription)"
                    statusText = externalStatusText
                    await loadProperties()
                    return
                }
            }
            showExternalsEditor = false
            statusText = updateExternalsAfterSave ? "已保存并更新外部项" : "已保存 svn:externals"
            await loadProperties()
        } catch {
            externalStatusText = error.localizedDescription
            statusText = externalStatusText
        }
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
            statusText = "已保存 \(propertyName)"
        } else if case .error(let message) = viewModel?.state {
            statusText = "保存失败：\(message)"
        }
    }

    private func deletePendingProperty() async {
        guard let propertyName = pendingDeleteProperty else { return }
        pendingDeleteProperty = nil
        await viewModel?.delete(name: propertyName)
        if case .loaded = viewModel?.state {
            statusText = "已删除 \(propertyName)"
            if name == propertyName {
                name = ""
                value = ""
            }
        } else if case .error(let message) = viewModel?.state {
            statusText = "删除失败：\(message)"
        }
    }
}

private struct ExternalDefinitionDraft: Identifiable {
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
