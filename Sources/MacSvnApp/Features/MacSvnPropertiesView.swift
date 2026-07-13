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
            if navigator.pendingPropertyPath != nil {
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
    }

    private var availableTemplates: [SvnPropertyTemplate] {
        let isDirectory = selectedTargetIsDirectory
        return PropertyViewModel.commonTemplates.filter {
            isDirectory ? $0.appliesToDirectory : $0.appliesToFile
        }
    }

    private var selectedTargetIsDirectory: Bool {
        guard let record = workspaceController.selectedRecord, let path = selected.first else { return true }
        let target = path == "."
            ? URL(fileURLWithPath: record.localPath)
            : URL(fileURLWithPath: record.localPath).appendingPathComponent(path)
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
