import SwiftUI
import AppKit
import MacSvnCore

/// 设置页：svn 路径、日志批量、超时、分支布局、外部 Diff、AI。
public struct MacSvnSettingsView: View {
    @ObservedObject private var session: MacSvnAppSession
    @State private var svnPath: String = ""
    @State private var logBatchSize: Int = 100
    @State private var processTimeout: Double = 120
    @State private var progressAutoCloseMode: ProgressAutoCloseMode = .noConflicts
    @State private var shelvingVersion: SvnShelvingVersion = .v3
    @State private var logCacheEnabled = true
    @State private var logCacheRetentionDays = 90
    @State private var logCacheMaxEntries = 20_000
    @State private var hardBlockConflictMarkers = false
    @State private var trunk = "trunk"
    @State private var branches = "branches"
    @State private var tags = "tags"
    @State private var graphTrunkPatterns = "trunk/**\n**/trunk/**"
    @State private var graphBranchPatterns = "branches/*/**\n**/branches/*/**"
    @State private var graphTagPatterns = "tags/*/**\n**/tags/*/**"
    @State private var graphBlendCopyColors = true
    @State private var graphTrunkHex = "#2E7D32"
    @State private var graphBranchHex = "#1565C0"
    @State private var graphTagHex = "#AD1457"
    @State private var graphUnclassifiedHex = "#616161"
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
                Picker("官方 Shelve 实现", selection: $shelvingVersion) {
                    ForEach(SvnShelvingVersion.allCases, id: \.rawValue) { version in
                        Text(version.displayName).tag(version)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("行为") {
                Stepper("日志每批 \(logBatchSize) 条", value: $logBatchSize, in: 20...500, step: 20)
                Stepper("进程超时 \(Int(processTimeout)) 秒", value: $processTimeout, in: 30...600, step: 30)
                Toggle("提交守护：冲突标记硬阻断", isOn: $hardBlockConflictMarkers)
                Picker("进度完成后", selection: $progressAutoCloseMode) {
                    ForEach(ProgressAutoCloseMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text("更新/合并出现错误、冲突或合并增删时，进度提示会按策略保留。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("日志缓存") {
                Toggle("启用日志缓存", isOn: $logCacheEnabled)
                Stepper("保留 \(logCacheRetentionDays) 天", value: $logCacheRetentionDays, in: 1...365)
                    .disabled(!logCacheEnabled)
                Stepper("每个目标最多 \(logCacheMaxEntries) 条", value: $logCacheMaxEntries, in: 100...100_000, step: 100)
                    .disabled(!logCacheEnabled)
                Button("清理全部日志缓存") {
                    Task { await clearLogCache() }
                }
                Text("在线日志会按仓库与目标隔离保存；网络不可用时可回退到最近缓存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("分支布局") {
                TextField("trunk", text: $trunk)
                TextField("branches", text: $branches)
                TextField("tags", text: $tags)
            }
            Section("修订图") {
                patternEditor("主干 pattern（每行一个）", text: $graphTrunkPatterns)
                patternEditor("分支 pattern（每行一个）", text: $graphBranchPatterns)
                patternEditor("标签 pattern（每行一个）", text: $graphTagPatterns)
                Toggle("复制节点混合源颜色", isOn: $graphBlendCopyColors)
                colorPicker("主干颜色", hex: $graphTrunkHex)
                colorPicker("分支颜色", hex: $graphBranchHex)
                colorPicker("标签颜色", hex: $graphTagHex)
                colorPicker("未分类颜色", hex: $graphUnclassifiedHex)
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
        progressAutoCloseMode = settings.progressAutoCloseMode
        shelvingVersion = settings.shelvingVersion
        logCacheEnabled = settings.logCachePolicy.enabled
        logCacheRetentionDays = settings.logCachePolicy.retentionDays
        logCacheMaxEntries = settings.logCachePolicy.maxEntriesPerTarget
        hardBlockConflictMarkers = settings.commitGuardHardBlockConflictMarkers
        trunk = settings.branchLayout.trunk
        branches = settings.branchLayout.branches
        tags = settings.branchLayout.tags
        let graph = settings.revisionGraph
        graphTrunkPatterns = graph.trunkPatterns.joined(separator: "\n")
        graphBranchPatterns = graph.branchPatterns.joined(separator: "\n")
        graphTagPatterns = graph.tagPatterns.joined(separator: "\n")
        graphBlendCopyColors = graph.blendCopyColors
        graphTrunkHex = graph.palette.trunkHex
        graphBranchHex = graph.palette.branchHex
        graphTagHex = graph.palette.tagHex
        graphUnclassifiedHex = graph.palette.unclassifiedHex
        externalDiffName = settings.externalDiffTool?.name ?? ""
        externalDiffPath = settings.externalDiffTool?.executablePath ?? ""
    }

    private func save() async {
        var settings = await session.settingsStore.settings()
        let trimmed = svnPath.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.svnPath = trimmed.isEmpty ? nil : trimmed
        settings.logBatchSize = logBatchSize
        settings.processTimeout = processTimeout
        settings.progressAutoCloseMode = progressAutoCloseMode
        settings.shelvingVersion = shelvingVersion
        settings.logCachePolicy = LogCachePolicy(
            enabled: logCacheEnabled,
            retentionDays: logCacheRetentionDays,
            maxEntriesPerTarget: logCacheMaxEntries
        )
        settings.commitGuardHardBlockConflictMarkers = hardBlockConflictMarkers
        settings.branchLayout = BranchLayout(trunk: trunk, branches: branches, tags: tags)
        settings.revisionGraph = RevisionGraphSettings(
            trunkPatterns: patterns(from: graphTrunkPatterns),
            branchPatterns: patterns(from: graphBranchPatterns),
            tagPatterns: patterns(from: graphTagPatterns),
            blendCopyColors: graphBlendCopyColors,
            palette: RevisionGraphPalette(
                trunkHex: normalizedHex(graphTrunkHex, fallback: "#2E7D32"),
                branchHex: normalizedHex(graphBranchHex, fallback: "#1565C0"),
                tagHex: normalizedHex(graphTagHex, fallback: "#AD1457"),
                unclassifiedHex: normalizedHex(graphUnclassifiedHex, fallback: "#616161")
            )
        )
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
            statusText = "已保存。svn 路径、官方 Shelve 版本与提交守护策略将在下次启动会话后完全生效。"
        } catch {
            statusText = "保存失败：\(error.localizedDescription)"
        }
    }

    private func clearLogCache() async {
        do {
            try await session.logCacheStore.clearAll()
            statusText = "日志缓存已清理。"
        } catch {
            statusText = "清理日志缓存失败：\(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func patternEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 48, maxHeight: 72)
                .border(Color.secondary.opacity(0.25))
        }
    }

    private func colorPicker(_ title: String, hex: Binding<String>) -> some View {
        ColorPicker(
            title,
            selection: Binding(
                get: { Color(hex: hex.wrappedValue) },
                set: { hex.wrappedValue = $0.rgbHex }
            ),
            supportsOpacity: false
        )
    }

    private func patterns(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizedHex(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 7,
              trimmed.first == "#",
              UInt64(trimmed.dropFirst(), radix: 16) != nil else {
            return fallback
        }
        return trimmed.uppercased()
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let value = UInt64(cleaned, radix: 16) else {
            self = .secondary
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var rgbHex: String {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.gray
        return String(
            format: "#%02X%02X%02X",
            Int(round(nsColor.redComponent * 255)),
            Int(round(nsColor.greenComponent * 255)),
            Int(round(nsColor.blueComponent * 255))
        )
    }
}
