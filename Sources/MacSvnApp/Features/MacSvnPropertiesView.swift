import SwiftUI
import MacSvnCore

public struct MacSvnPropertiesView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    private let session: MacSvnAppSession

    @State private var paths: [String] = ["."]
    @State private var selected: Set<String> = ["."]
    @State private var viewModel: PropertyViewModel?
    @State private var name = ""
    @State private var value = ""
    @State private var statusText: String?

    public init(workspaceController: MacSvnWorkspaceController, session: MacSvnAppSession) {
        self.workspaceController = workspaceController
        self.session = session
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
                            .contextMenu {
                                Button("删除", role: .destructive) {
                                    Task {
                                        await viewModel?.delete(name: prop.name)
                                        statusText = "已删除 \(prop.name)"
                                    }
                                }
                            }
                        }
                        Form {
                            Section("新增/修改") {
                                Picker("模板", selection: $name) {
                                    Text("自定义").tag("")
                                    ForEach(PropertyViewModel.commonTemplates, id: \.name) { template in
                                        Text(template.name).tag(template.name)
                                    }
                                }
                                .onChange(of: name) { _, newValue in
                                    if let template = PropertyViewModel.commonTemplates.first(where: { $0.name == newValue }) {
                                        value = template.defaultValue
                                    }
                                }
                                TextField("名称", text: $name)
                                TextField("值", text: $value)
                                Button("保存") {
                                    Task {
                                        await viewModel?.save(name: name, value: value)
                                        statusText = "已保存 \(name)"
                                    }
                                }
                            }
                        }
                        .formStyle(.grouped)
                    }
                    .frame(minWidth: 360)
                }
            }
        }
        .task { await reloadPaths(); await loadProperties() }
        .onChange(of: workspaceController.selectedID) { _, _ in
            Task { await reloadPaths(); await loadProperties() }
        }
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
}
