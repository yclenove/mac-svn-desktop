import SwiftUI
import AppKit
import MacSvnCore

/// 设置页：svn 路径、日志批量、超时、分支布局、外部 Diff、AI。
public struct MacSvnSettingsView: View {
    @ObservedObject private var session: MacSvnAppSession
    @State private var selectedCategory: MacSvnSettingsCategory? = .general
    @State private var svnPath: String = ""
    @State private var logBatchSize: Int = 100
    @State private var processTimeout: Double = 120
    @State private var progressAutoCloseMode: ProgressAutoCloseMode = .noConflicts
    @State private var shelvingVersion: SvnShelvingVersion = .v3
    @State private var logCacheEnabled = true
    @State private var logCacheRetentionDays = 90
    @State private var logCacheMaxEntries = 20_000
    @State private var clientHooks: [ClientHookConfiguration] = []
    @State private var finderSyncCacheMode: FinderSyncCacheMode = .defaultCache
    @State private var finderSyncIncludedPaths = ""
    @State private var finderSyncExcludedPaths = ""
    @State private var finderSyncEnabledBadges = Set(FinderSyncBadge.allCases)
    @State private var finderSyncPromotedCommandIDs = Set(FinderSyncContextMenuSettings.defaultPromotedCommandIDs)
    @State private var finderSyncPromoteLockForNeedsLock = true
    @State private var finderSyncHideUnversionedMenus = false
    @State private var finderSyncMenuExcludedPaths = ""
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
    @State private var externalDiffArguments = ""
    @State private var externalToolRules: [ExternalToolRule] = []
    @State private var statusText: String?
    @State private var showAISettings = false
    @State private var showClearAuthenticationConfirmation = false
    @State private var isClearingAuthenticationCache = false
    @State private var isClearingLogCache = false

    public init(session: MacSvnAppSession) {
        self.session = session
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                List(selection: $selectedCategory) {
                    ForEach(MacSvnSettingsCategory.allCases) { category in
                        Label(category.title, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: 176, idealWidth: 190, maxWidth: 210)

                Divider()

                Form {
                    categoryContent
                }
                .formStyle(.grouped)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            HStack(spacing: 12) {
                if let statusText {
                    Text(statusText)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("保存") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 720, minHeight: 520)
        .navigationTitle("设置 · \((selectedCategory ?? .general).title)")
        .task { await load() }
        .sheet(isPresented: $showAISettings) {
            MacSvnAIProviderSettingsView(session: session)
                .frame(minWidth: 640, minHeight: 520)
        }
        .confirmationDialog(
            "清除 Subversion 认证缓存？",
            isPresented: $showClearAuthenticationConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除认证缓存", role: .destructive) {
                Task { await clearAuthenticationCache() }
            }
        } message: {
            Text("将清除当前用户 Subversion 客户端管理的 auth 文件和 Keychain 凭据。下次访问仓库时需要重新输入凭据。不会删除 AI Provider 凭据。")
        }
    }

    @ViewBuilder
    private var categoryContent: some View {
        switch selectedCategory ?? .general {
        case .general:
            generalSettings
        case .dialogs:
            dialogSettings
        case .colours:
            colourSettings
        case .network:
            networkSettings
        case .externalPrograms:
            externalProgramSettings
        case .savedData:
            savedDataSettings
        case .finder:
            finderSettings
        case .revisionGraph:
            revisionGraphSettings
        case .ai:
            aiSettings
        }
    }

    @ViewBuilder
    private var generalSettings: some View {
        Section("Subversion") {
            TextField("svn 可执行路径", text: $svnPath)
            LabeledContent("当前会话路径", value: session.svnExecutablePath)
        }
        Section("分支布局") {
            TextField("trunk", text: $trunk)
            TextField("branches", text: $branches)
            TextField("tags", text: $tags)
        }
    }

    @ViewBuilder
    private var dialogSettings: some View {
        Section("Dialogs 1") {
            Stepper("日志每批 \(logBatchSize) 条", value: $logBatchSize, in: 20...500, step: 20)
            Picker("进度完成后", selection: $progressAutoCloseMode) {
                ForEach(ProgressAutoCloseMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        }
        Section("Dialogs 2") {
            Toggle("提交守护：冲突标记硬阻断", isOn: $hardBlockConflictMarkers)
        }
        Section("Dialogs 3") {
            Picker("官方 Shelve 实现", selection: $shelvingVersion) {
                ForEach(SvnShelvingVersion.allCases, id: \.rawValue) { version in
                    Text(version.displayName).tag(version)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var colourSettings: some View {
        Section("Revision Graph") {
            colorPicker("主干颜色", hex: $graphTrunkHex)
            colorPicker("分支颜色", hex: $graphBranchHex)
            colorPicker("标签颜色", hex: $graphTagHex)
            colorPicker("未分类颜色", hex: $graphUnclassifiedHex)
        }
    }

    @ViewBuilder
    private var networkSettings: some View {
        Section("Subversion Network") {
            Stepper(
                "进程超时 \(Int(processTimeout)) 秒",
                value: $processTimeout,
                in: 30...600,
                step: 30
            )
        }
    }

    @ViewBuilder
    private var externalProgramSettings: some View {
        Section("Unified Diff Viewer") {
            TextField("名称（如 Kaleidoscope）", text: $externalDiffName)
            TextField("可执行路径", text: $externalDiffPath)
            TextEditor(text: $externalDiffArguments)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 54)
        }
        Section("按扩展名") {
            ForEach($externalToolRules) { rule in
                externalToolRuleEditor(rule)
            }
            Button {
                externalToolRules.append(ExternalToolRule(
                    purpose: .diff,
                    tool: ExternalDiffToolConfiguration(name: "", executablePath: "", arguments: [])
                ))
            } label: {
                Label("添加规则", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private var savedDataSettings: some View {
        Section("认证缓存") {
            Text("管理当前用户 Subversion 配置目录中的认证数据。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("清除 Subversion 认证缓存…", role: .destructive) {
                showClearAuthenticationConfirmation = true
            }
            .disabled(isClearingAuthenticationCache)
        }
        Section("Hook Scripts") {
            ForEach($clientHooks) { $hook in
                clientHookEditor($hook)
            }
            Button {
                clientHooks.append(ClientHookConfiguration(
                    type: .preCommit,
                    workingCopyPath: "",
                    executablePath: ""
                ))
            } label: {
                Label("添加钩子", systemImage: "plus")
            }
        }
        Section("日志缓存") {
            Toggle("启用日志缓存", isOn: $logCacheEnabled)
            Stepper("保留 \(logCacheRetentionDays) 天", value: $logCacheRetentionDays, in: 1...365)
                .disabled(!logCacheEnabled)
            Stepper(
                "每个目标最多 \(logCacheMaxEntries) 条",
                value: $logCacheMaxEntries,
                in: 100...100_000,
                step: 100
            )
            .disabled(!logCacheEnabled)
            Button("清理全部日志缓存") {
                Task { await clearLogCache() }
            }
            .disabled(isClearingLogCache)
        }
    }

    @ViewBuilder
    private func clientHookEditor(_ hook: Binding<ClientHookConfiguration>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("启用", isOn: hook.isEnabled)
                Picker("类型", selection: hook.type) {
                    ForEach(ClientHookType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .frame(maxWidth: 240)
                Spacer()
                Button(role: .destructive) {
                    clientHooks.removeAll { $0.id == hook.wrappedValue.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除钩子")
            }
            HStack {
                TextField("工作副本根路径", text: hook.workingCopyPath)
                Button {
                    chooseDirectory(for: hook.workingCopyPath)
                } label: {
                    Image(systemName: "folder")
                }
                .help("选择工作副本根目录")
            }
            HStack {
                TextField("脚本或可执行文件", text: hook.executablePath)
                Button {
                    chooseExecutable(for: hook.executablePath)
                } label: {
                    Image(systemName: "doc.badge.gearshape")
                }
                .help("选择脚本或可执行文件")
            }
            patternEditor("自定义参数（每行一个；官方钩子参数会自动追加）", text: hookArgumentsBinding(hook))
            Stepper(
                "超时 \(Int(hook.wrappedValue.timeout)) 秒",
                value: hook.timeout,
                in: 1...600,
                step: 5
            )
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var finderSettings: some View {
        Section("Finder 角标") {
            Picker("Status Cache", selection: $finderSyncCacheMode) {
                ForEach(FinderSyncCacheMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            patternEditor("包含路径（每行一个；留空包含全部工作副本）", text: $finderSyncIncludedPaths)
            patternEditor("排除路径（每行一个；优先于包含路径）", text: $finderSyncExcludedPaths)
            DisclosureGroup("显示的角标种类") {
                HStack {
                    Button("全选") {
                        finderSyncEnabledBadges = Set(FinderSyncBadge.allCases)
                    }
                    Button("清空") {
                        finderSyncEnabledBadges.removeAll()
                    }
                }
                ForEach(FinderSyncBadge.allCases, id: \.self) { badge in
                    Toggle(badge.displayName, isOn: finderSyncBadgeBinding(badge))
                }
            }
        }
        Section("Finder 菜单") {
            DisclosureGroup("提升到顶层的命令") {
                ForEach(SvnCommandCatalog.dailyCFMCommands, id: \.id) { descriptor in
                    Toggle(
                        descriptor.displayName,
                        isOn: finderSyncPromotedCommandBinding(descriptor.id)
                    )
                }
            }
            Toggle("needs-lock 文件自动提升 Lock", isOn: $finderSyncPromoteLockForNeedsLock)
            Toggle("未版本控制/已忽略路径隐藏菜单", isOn: $finderSyncHideUnversionedMenus)
            patternEditor("菜单排除路径（每行一个）", text: $finderSyncMenuExcludedPaths)
        }
    }

    @ViewBuilder
    private var revisionGraphSettings: some View {
        Section("分类") {
            patternEditor("主干 pattern（每行一个）", text: $graphTrunkPatterns)
            patternEditor("分支 pattern（每行一个）", text: $graphBranchPatterns)
            patternEditor("标签 pattern（每行一个）", text: $graphTagPatterns)
            Toggle("复制节点混合源颜色", isOn: $graphBlendCopyColors)
        }
    }

    @ViewBuilder
    private var aiSettings: some View {
        Section("AI Provider") {
            Button("打开 AI Provider / 隐私 / 连通性测试…") {
                showAISettings = true
            }
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
        clientHooks = settings.clientHooks
        finderSyncCacheMode = settings.finderSyncCacheMode
        finderSyncIncludedPaths = settings.finderSyncOverlaySettings.includedPaths.joined(separator: "\n")
        finderSyncExcludedPaths = settings.finderSyncOverlaySettings.excludedPaths.joined(separator: "\n")
        finderSyncEnabledBadges = settings.finderSyncOverlaySettings.enabledBadges
        finderSyncPromotedCommandIDs = Set(settings.finderSyncContextMenuSettings.promotedCommandIDs)
        finderSyncPromoteLockForNeedsLock = settings.finderSyncContextMenuSettings.promoteLockForNeedsLock
        finderSyncHideUnversionedMenus = settings.finderSyncContextMenuSettings.hideMenusForUnversionedItems
        finderSyncMenuExcludedPaths = settings.finderSyncContextMenuSettings.excludedPaths.joined(separator: "\n")
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
        externalDiffArguments = settings.externalDiffTool?.arguments.joined(separator: "\n") ?? ""
        externalToolRules = settings.externalToolRules
    }

    private func save() async {
        if let invalidHook = clientHooks.first(where: {
            $0.isEnabled && (
                $0.workingCopyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || $0.executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }) {
            statusText = "无法保存：\(invalidHook.type.displayName) 钩子需要工作副本路径和脚本路径。"
            return
        }
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
        settings.clientHooks = clientHooks
        settings.finderSyncCacheMode = finderSyncCacheMode
        settings.finderSyncOverlaySettings = FinderSyncOverlaySettings(
            includedPaths: patterns(from: finderSyncIncludedPaths),
            excludedPaths: patterns(from: finderSyncExcludedPaths),
            enabledBadges: finderSyncEnabledBadges
        )
        settings.finderSyncContextMenuSettings = FinderSyncContextMenuSettings(
            promotedCommandIDs: SvnCommandCatalog.dailyCFMCommandIDs.filter {
                finderSyncPromotedCommandIDs.contains($0)
            },
            promoteLockForNeedsLock: finderSyncPromoteLockForNeedsLock,
            hideMenusForUnversionedItems: finderSyncHideUnversionedMenus,
            excludedPaths: patterns(from: finderSyncMenuExcludedPaths)
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
                executablePath: toolPath,
                arguments: externalToolArguments(from: externalDiffArguments)
            )
        } else {
            settings.externalDiffTool = nil
        }
        guard let normalizedRules = normalizedExternalToolRules() else {
            return
        }
        settings.externalToolRules = normalizedRules
        do {
            try await session.settingsStore.update(settings)
        } catch {
            statusText = "保存失败：\(error.localizedDescription)"
            return
        }

        let records = await session.workspaceStore.records()
        do {
            try FinderSyncRootsExporter.export(
                records: records,
                cacheMode: settings.finderSyncCacheMode,
                overlaySettings: settings.finderSyncOverlaySettings,
                contextMenuSettings: settings.finderSyncContextMenuSettings,
                to: session.finderSyncConfigurationFileURLs
            )
        } catch {
            statusText = "设置已保存，但 Finder 扩展配置同步失败：\(error.localizedDescription)"
            return
        }
        statusText = "已保存。svn 路径、客户端钩子、官方 Shelve 版本与提交守护策略将在下次启动会话后完全生效。"
    }

    @ViewBuilder
    private func externalToolRuleEditor(_ rule: Binding<ExternalToolRule>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("用途", selection: rule.purpose) {
                    ForEach(ExternalToolPurpose.allCases) { purpose in
                        Text(purpose.displayName).tag(purpose)
                    }
                }
                .frame(maxWidth: 180)
                Spacer()
                Button(role: .destructive) {
                    externalToolRules.removeAll { $0.id == rule.wrappedValue.id }
                } label: {
                    Image(systemName: "trash")
                }
                .help("删除规则")
            }
            TextField("扩展名（逗号分隔；留空为默认）", text: externalToolExtensionsText(rule))
            TextField("名称", text: rule.tool.name)
            TextField("可执行路径", text: rule.tool.executablePath)
            TextEditor(text: externalToolArgumentsText(rule))
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 48)
        }
        .padding(.vertical, 6)
    }

    private func externalToolExtensionsText(_ rule: Binding<ExternalToolRule>) -> Binding<String> {
        Binding(
            get: { rule.wrappedValue.fileExtensions.joined(separator: ", ") },
            set: { rule.wrappedValue.fileExtensions = externalToolExtensions(from: $0) }
        )
    }

    private func externalToolArgumentsText(_ rule: Binding<ExternalToolRule>) -> Binding<String> {
        Binding(
            get: { rule.wrappedValue.tool.arguments.joined(separator: "\n") },
            set: { rule.wrappedValue.tool.arguments = externalToolArguments(from: $0) }
        )
    }

    private func externalToolExtensions(from text: String) -> [String] {
        text
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func externalToolArguments(from text: String) -> [String] {
        text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizedExternalToolRules() -> [ExternalToolRule]? {
        var seenKeys = Set<String>()
        var normalized: [ExternalToolRule] = []
        for rule in externalToolRules {
            let name = rule.tool.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let path = rule.tool.executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !path.isEmpty else {
                statusText = "无法保存：外置工具规则需要名称和可执行路径。"
                return nil
            }
            var copy = rule
            copy.fileExtensions = rule.fileExtensions.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
            copy.tool = ExternalDiffToolConfiguration(
                name: name,
                executablePath: path,
                arguments: rule.tool.arguments.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty }
            )
            let keys = copy.fileExtensions.isEmpty ? ["*"] : copy.fileExtensions.map {
                $0.lowercased().replacingOccurrences(of: "*.", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "."))
            }
            for key in keys {
                guard seenKeys.insert("\(copy.purpose.rawValue):\(key)").inserted else {
                    statusText = "无法保存：同一用途不能重复配置扩展名 \(key)。"
                    return nil
                }
            }
            normalized.append(copy)
        }
        return normalized
    }

    private func clearLogCache() async {
        guard !isClearingLogCache else { return }
        isClearingLogCache = true
        defer { isClearingLogCache = false }
        do {
            try await session.logCacheStore.clearAll()
            statusText = "日志缓存已清理。"
        } catch {
            statusText = "清理日志缓存失败：\(error.localizedDescription)"
        }
    }

    private func clearAuthenticationCache() async {
        guard !isClearingAuthenticationCache else { return }
        isClearingAuthenticationCache = true
        defer { isClearingAuthenticationCache = false }
        do {
            let result = try await session.svnAuthenticationCacheStore.clearAll()
            if result.removedFileCacheItemCount == 0 {
                statusText = "已完成 Subversion 认证缓存清理。"
            } else {
                statusText = "已完成 Subversion 认证缓存清理（移除 \(result.removedFileCacheItemCount) 项文件缓存）。"
            }
        } catch {
            statusText = "清理 Subversion 认证缓存失败：\(error.localizedDescription)"
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

    private func finderSyncBadgeBinding(_ badge: FinderSyncBadge) -> Binding<Bool> {
        Binding(
            get: { finderSyncEnabledBadges.contains(badge) },
            set: { isEnabled in
                if isEnabled {
                    finderSyncEnabledBadges.insert(badge)
                } else {
                    finderSyncEnabledBadges.remove(badge)
                }
            }
        )
    }

    private func finderSyncPromotedCommandBinding(_ commandID: SvnCommandID) -> Binding<Bool> {
        Binding(
            get: { finderSyncPromotedCommandIDs.contains(commandID) },
            set: { isPromoted in
                if isPromoted {
                    finderSyncPromotedCommandIDs.insert(commandID)
                } else {
                    finderSyncPromotedCommandIDs.remove(commandID)
                }
            }
        )
    }

    private func patterns(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func hookArgumentsBinding(
        _ hook: Binding<ClientHookConfiguration>
    ) -> Binding<String> {
        Binding(
            get: { hook.wrappedValue.arguments.joined(separator: "\n") },
            set: { hook.wrappedValue.arguments = patterns(from: $0) }
        )
    }

    private func chooseDirectory(for path: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            path.wrappedValue = url.path
        }
    }

    private func chooseExecutable(for path: Binding<String>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            path.wrappedValue = url.path
        }
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
