import SwiftUI
import MacSvnCore

/// 设置页：svn 路径、日志批量、超时、分支布局、外部 Diff、AI。
public struct MacSvnSettingsView: View {
    @ObservedObject private var session: MacSvnAppSession
    @State private var svnPath: String = ""
    @State private var logBatchSize: Int = 100
    @State private var processTimeout: Double = 120
    @State private var hardBlockConflictMarkers = false
    @State private var trunk = "trunk"
    @State private var branches = "branches"
    @State private var tags = "tags"
    @State private var externalDiffName = ""
    @State private var externalDiffPath = ""
    @State private var statusText: String?
    @State private var showAISettings = false

    public init(session: MacSvnAppSession) {
        self.session = session
    }

    public var body: some View {
        Form {
            Section("Subversion") {
                TextField("svn 可执行路径", text: $svnPath)
                LabeledContent("当前会话路径", value: session.svnExecutablePath)
            }
            Section("行为") {
                Stepper("日志每批 \(logBatchSize) 条", value: $logBatchSize, in: 20...500, step: 20)
                Stepper("进程超时 \(Int(processTimeout)) 秒", value: $processTimeout, in: 30...600, step: 30)
                Toggle("提交守护：冲突标记硬阻断", isOn: $hardBlockConflictMarkers)
            }
            Section("分支布局") {
                TextField("trunk", text: $trunk)
                TextField("branches", text: $branches)
                TextField("tags", text: $tags)
            }
            Section("外部 Diff 工具（可选）") {
                TextField("名称（如 Kaleidoscope）", text: $externalDiffName)
                TextField("可执行路径", text: $externalDiffPath)
            }
            Section("AI") {
                Button("打开 AI Provider / 隐私 / 连通性测试…") {
                    showAISettings = true
                }
                Text("本机可先运行 scripts/seed-volcengine-ark.sh 注入火山方舟（Key 仅进 Keychain）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let statusText {
                Text(statusText)
                    .foregroundStyle(.secondary)
            }
            Button("保存") {
                Task { await save() }
            }
            .keyboardShortcut(.defaultAction)
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("设置")
        .task { await load() }
        .sheet(isPresented: $showAISettings) {
            MacSvnAIProviderSettingsView(session: session)
                .frame(minWidth: 640, minHeight: 520)
        }
    }

    private func load() async {
        let settings = await session.settingsStore.settings()
        svnPath = settings.svnPath ?? ""
        logBatchSize = settings.logBatchSize
        processTimeout = settings.processTimeout
        hardBlockConflictMarkers = settings.commitGuardHardBlockConflictMarkers
        trunk = settings.branchLayout.trunk
        branches = settings.branchLayout.branches
        tags = settings.branchLayout.tags
        externalDiffName = settings.externalDiffTool?.name ?? ""
        externalDiffPath = settings.externalDiffTool?.executablePath ?? ""
    }

    private func save() async {
        var settings = await session.settingsStore.settings()
        let trimmed = svnPath.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.svnPath = trimmed.isEmpty ? nil : trimmed
        settings.logBatchSize = logBatchSize
        settings.processTimeout = processTimeout
        settings.commitGuardHardBlockConflictMarkers = hardBlockConflictMarkers
        settings.branchLayout = BranchLayout(trunk: trunk, branches: branches, tags: tags)
        let toolName = externalDiffName.trimmingCharacters(in: .whitespacesAndNewlines)
        let toolPath = externalDiffPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !toolName.isEmpty, !toolPath.isEmpty {
            settings.externalDiffTool = ExternalDiffToolConfiguration(
                name: toolName,
                executablePath: toolPath
            )
        } else {
            settings.externalDiffTool = nil
        }
        do {
            try await session.settingsStore.update(settings)
            statusText = "已保存。svn 路径与提交守护策略将在下次启动会话后完全生效。"
        } catch {
            statusText = "保存失败：\(error.localizedDescription)"
        }
    }
}
