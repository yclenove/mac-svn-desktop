import SwiftUI
import AppKit
import MacSvnCore

struct SettingsDraftSnapshot: Equatable {
    let svnPath: String
    let logBatchSize: Int
    let processTimeout: Double
    let progressAutoCloseMode: ProgressAutoCloseMode
    let shelvingVersion: SvnShelvingVersion
    let logCacheEnabled: Bool
    let logCacheRetentionDays: Int
    let logCacheMaxEntries: Int
    let clientHooks: [ClientHookConfiguration]
    let finderSyncCacheMode: FinderSyncCacheMode
    let finderSyncIncludedPaths: String
    let finderSyncExcludedPaths: String
    let finderSyncEnabledBadges: Set<FinderSyncBadge>
    let finderSyncPromotedCommandIDs: Set<SvnCommandID>
    let finderSyncPromoteLockForNeedsLock: Bool
    let finderSyncHideUnversionedMenus: Bool
    let finderSyncMenuExcludedPaths: String
    let hardBlockConflictMarkers: Bool
    let trunk: String
    let branches: String
    let tags: String
    let graphTrunkPatterns: String
    let graphBranchPatterns: String
    let graphTagPatterns: String
    let graphBlendCopyColors: Bool
    let graphTrunkHex: String
    let graphBranchHex: String
    let graphTagHex: String
    let graphUnclassifiedHex: String
    let externalDiffName: String
    let externalDiffPath: String
    let externalDiffArguments: String
    let externalToolRules: [ExternalToolRule]
    let generalPreferences: GeneralSettings
    let dialogPreferences: DialogSettings
    let changeColours: ChangeColourPalette
    let networkPreferences: SvnNetworkSettings
    let proxyPassword: String
    let globalIgnorePatterns: String
    let useCommitTimes: Bool
}

/// 设置页：svn 路径、日志批量、超时、分支布局、外部 Diff、AI。
public struct MacSvnSettingsView: View {
    @Environment(\.locale) private var locale
    @ObservedObject private var session: MacSvnAppSession
    @State private var selectedCategory: MacSvnSettingsCategory? = .general
    @State private var settingsSearchText = ""
    @State private var baselineDraft: SettingsDraftSnapshot?
    @State private var isLoading = true
    @State private var isSaving = false
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
    @State private var generalPreferences = GeneralSettings()
    @State private var dialogPreferences = DialogSettings()
    @State private var changeColours = ChangeColourPalette()
    @State private var networkPreferences = SvnNetworkSettings()
    @State private var proxyPassword = ""
    @State private var globalIgnorePatterns = ""
    @State private var useCommitTimes = false
    @State private var colourAppearance: AppAppearance = .light
    @State private var feedback: MacSvnAuxiliaryFeedback?
    @State private var showAISettings = false
    @State private var showClearAuthenticationConfirmation = false
    @State private var isClearingAuthenticationCache = false
    @State private var isClearingLogCache = false
    @FocusState private var isSettingsSearchFocused: Bool

    public init(session: MacSvnAppSession) {
        self.session = session
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                settingsSidebar

                Divider()

                if filteredCategories.isEmpty {
                    ContentUnavailableView {
                        Label("没有匹配的设置", systemImage: "magnifyingglass")
                    } description: {
                        Text("换个关键词，或清除搜索后查看全部九类设置。")
                    } actions: {
                        Button("清除搜索") {
                            settingsSearchText = ""
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        categoryContent
                    }
                    .formStyle(.grouped)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .disabled(isLoading || isSaving)
                }
            }

            Divider()
            settingsActionBar
        }
        .frame(minWidth: 720, minHeight: 520)
        .navigationTitle(settingsNavigationTitle)
        .background {
            Button("") { isSettingsSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .task { await load() }
        .onChange(of: settingsSearchText) { _, _ in
            synchronizeSettingsCategorySelection()
        }
        .onChange(of: hasUnsavedChanges) { _, isDirty in
            if isDirty, !isSaving {
                feedback = nil
            }
        }
        .sheet(isPresented: $showAISettings) {
            MacSvnAIProviderSettingsView(session: session)
                .frame(minWidth: 640, minHeight: 520)
                .macSvnDismissibleSheet()
        }
        .confirmationDialog(
            "清除 Subversion 认证缓存？",
            isPresented: $showClearAuthenticationConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除认证缓存", role: .destructive) {
                Task { await clearAuthenticationCache() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清除当前用户 Subversion 客户端管理的 auth 文件和 Keychain 凭据。下次访问仓库时需要重新输入凭据。不会删除 AI Provider 凭据。")
        }
    }

    private var filteredCategories: [MacSvnSettingsCategory] {
        MacSvnSettingsCategory.allCases.filter { $0.matches(search: settingsSearchText) }
    }

    private var currentDraft: SettingsDraftSnapshot {
        SettingsDraftSnapshot(
            svnPath: svnPath,
            logBatchSize: logBatchSize,
            processTimeout: processTimeout,
            progressAutoCloseMode: progressAutoCloseMode,
            shelvingVersion: shelvingVersion,
            logCacheEnabled: logCacheEnabled,
            logCacheRetentionDays: logCacheRetentionDays,
            logCacheMaxEntries: logCacheMaxEntries,
            clientHooks: clientHooks,
            finderSyncCacheMode: finderSyncCacheMode,
            finderSyncIncludedPaths: finderSyncIncludedPaths,
            finderSyncExcludedPaths: finderSyncExcludedPaths,
            finderSyncEnabledBadges: finderSyncEnabledBadges,
            finderSyncPromotedCommandIDs: finderSyncPromotedCommandIDs,
            finderSyncPromoteLockForNeedsLock: finderSyncPromoteLockForNeedsLock,
            finderSyncHideUnversionedMenus: finderSyncHideUnversionedMenus,
            finderSyncMenuExcludedPaths: finderSyncMenuExcludedPaths,
            hardBlockConflictMarkers: hardBlockConflictMarkers,
            trunk: trunk,
            branches: branches,
            tags: tags,
            graphTrunkPatterns: graphTrunkPatterns,
            graphBranchPatterns: graphBranchPatterns,
            graphTagPatterns: graphTagPatterns,
            graphBlendCopyColors: graphBlendCopyColors,
            graphTrunkHex: graphTrunkHex,
            graphBranchHex: graphBranchHex,
            graphTagHex: graphTagHex,
            graphUnclassifiedHex: graphUnclassifiedHex,
            externalDiffName: externalDiffName,
            externalDiffPath: externalDiffPath,
            externalDiffArguments: externalDiffArguments,
            externalToolRules: externalToolRules,
            generalPreferences: generalPreferences,
            dialogPreferences: dialogPreferences,
            changeColours: changeColours,
            networkPreferences: networkPreferences,
            proxyPassword: proxyPassword,
            globalIgnorePatterns: globalIgnorePatterns,
            useCommitTimes: useCommitTimes
        )
    }

    private var hasUnsavedChanges: Bool {
        guard let baselineDraft else { return false }
        return currentDraft != baselineDraft
    }

    private var settingsNavigationTitle: String {
        guard let selectedCategory else { return "设置" }
        return "设置 · \(selectedCategory.title)"
    }

    @ViewBuilder
    private var settingsSidebar: some View {
        if #available(macOS 15.0, *) {
            settingsCategoryList
                .searchable(text: $settingsSearchText, placement: .sidebar, prompt: "搜索设置")
                .searchFocused($isSettingsSearchFocused)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("搜索设置", text: $settingsSearchText)
                        .textFieldStyle(.plain)
                        .focused($isSettingsSearchFocused)
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                Divider()
                settingsCategoryList
            }
        }
    }

    private var settingsCategoryList: some View {
        List(selection: $selectedCategory) {
            ForEach(filteredCategories) { category in
                Label {
                    Text(LocalizedStringKey(category.title))
                } icon: {
                    Image(systemName: category.systemImage)
                }
                .tag(category)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200, idealWidth: 220, maxWidth: 250)
    }

    private var settingsActionBar: some View {
        HStack(spacing: 10) {
            settingsActionStatus
            Spacer(minLength: 12)
            Button {
                Task { await reloadSettings() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("重新加载设置")
            .accessibilityLabel("重新加载设置")
            .keyboardShortcut("r", modifiers: .command)
            .disabled(isLoading || isSaving || hasUnsavedChanges)

            Button("保存", systemImage: "square.and.arrow.down") {
                Task { await save() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!hasUnsavedChanges || isSaving)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(.bar)
    }

    @ViewBuilder
    private var settingsActionStatus: some View {
        MacSvnInlineFeedbackView(feedback: currentSettingsFeedback)
            .frame(maxWidth: .infinity)
    }

    private var currentSettingsFeedback: MacSvnAuxiliaryFeedback? {
        if isLoading {
            return MacSvnAuxiliaryFeedback.localized(
                kind: .progress,
                message: "正在加载设置",
                locale: locale,
                diagnostic: nil
            )
        }
        if isSaving {
            return MacSvnAuxiliaryFeedback.localized(
                kind: .progress,
                message: "正在保存",
                locale: locale,
                diagnostic: nil
            )
        }
        if let feedback {
            return feedback
        }
        if hasUnsavedChanges {
            return MacSvnAuxiliaryFeedback.localized(
                kind: .warning,
                message: "未保存的更改",
                locale: locale,
                diagnostic: nil
            )
        }
        if baselineDraft != nil {
            return MacSvnAuxiliaryFeedback.localized(
                kind: .success,
                message: "所有更改已保存",
                locale: locale,
                diagnostic: nil
            )
        }
        return nil
    }

    private func synchronizeSettingsCategorySelection() {
        guard !filteredCategories.isEmpty else {
            selectedCategory = nil
            return
        }
        if let selectedCategory, filteredCategories.contains(selectedCategory) {
            return
        }
        selectedCategory = filteredCategories.first
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
        Section("应用") {
            Picker("界面语言", selection: $generalPreferences.language) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(LocalizedStringKey(language.displayName)).tag(language)
                }
            }
            Toggle("自动检查更新", isOn: $generalPreferences.checkForUpdatesAutomatically)
            HStack {
                Button("立即检查更新") {
                    Task { await session.checkForUpdates() }
                }
                updateStatusView
            }
        }
        Section("Subversion") {
            TextField("svn 可执行路径", text: $svnPath)
            LabeledContent("当前会话路径", value: session.svnExecutablePath)
            patternEditor("Global ignore（每行一个 pattern）", text: $globalIgnorePatterns)
            Toggle("使用最后提交时间", isOn: $useCommitTimes)
            Toggle(
                "应用本地修改的 svn:externals",
                isOn: $generalPreferences.applyLocalExternalsPropertyChanges
            )
            HStack {
                Button("编辑 SVN config") { openSvnConfig() }
                Button("编辑 SVN servers") { openSvnServers() }
            }
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
            TextField("日志字体", text: optionalStringBinding($dialogPreferences.logFontName))
            Stepper(
                "日志字体大小 \(Int(dialogPreferences.logFontSize))",
                value: $dialogPreferences.logFontSize,
                in: 9...28,
                step: 1
            )
            Toggle("短日期/时间", isOn: $dialogPreferences.useShortDateFormat)
            Toggle(
                "双击日志修订时与前一修订比较",
                isOn: $dialogPreferences.doubleClickLogToComparePrevious
            )
            Picker("进度完成后", selection: $progressAutoCloseMode) {
                ForEach(ProgressAutoCloseMode.allCases, id: \.self) { mode in
                    Text(LocalizedStringKey(mode.displayName)).tag(mode)
                }
            }
            Toggle("还原前移到废纸篓", isOn: $dialogPreferences.useTrashWhenReverting)
            HStack {
                TextField("默认 Checkout 路径", text: $dialogPreferences.defaultCheckoutPath)
                Button {
                    chooseDirectory(for: $dialogPreferences.defaultCheckoutPath)
                } label: {
                    Image(systemName: "folder")
                }
                .help("选择默认 Checkout 目录")
            }
            TextField("默认 Checkout URL", text: $dialogPreferences.defaultCheckoutURL)
        }
        Section("Dialogs 2") {
            Toggle("递归显示未版本目录", isOn: $dialogPreferences.recurseIntoUnversionedFolders)
            Toggle("提交说明自动完成", isOn: $dialogPreferences.enableCommitAutoCompletion)
            Stepper(
                "自动完成超时 \(dialogPreferences.autoCompletionTimeoutSeconds) 秒",
                value: $dialogPreferences.autoCompletionTimeoutSeconds,
                in: 1...60
            )
            .disabled(!dialogPreferences.enableCommitAutoCompletion)
            Stepper(
                "提交说明历史 \(dialogPreferences.commitMessageHistoryLimit) 条",
                value: $dialogPreferences.commitMessageHistoryLimit,
                in: 1...200
            )
            Toggle("自动勾选版本化修改", isOn: $dialogPreferences.selectCommitItemsAutomatically)
            Toggle(
                "提交后仍有改动时重开",
                isOn: $dialogPreferences.reopenCommitAfterSuccessWithRemainingItems
            )
            Toggle("启动时联系仓库", isOn: $dialogPreferences.contactRepositoryOnChangesOpen)
            Toggle("获取锁前显示对话框", isOn: $dialogPreferences.showLockDialogBeforeLocking)
            Toggle("提交守护：冲突标记硬阻断", isOn: $hardBlockConflictMarkers)
        }
        Section("Dialogs 3") {
            Toggle("预取仓库子目录", isOn: $dialogPreferences.preFetchRepositoryDirectories)
            Toggle("显示 svn:externals", isOn: $dialogPreferences.showRepositoryExternals)
            Picker("官方 Shelve 实现", selection: $shelvingVersion) {
                ForEach(SvnShelvingVersion.allCases, id: \.rawValue) { version in
                    Text(LocalizedStringKey(version.displayName)).tag(version)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var colourSettings: some View {
        Section("工作副本状态") {
            Picker("外观", selection: $colourAppearance) {
                Text("亮色").tag(AppAppearance.light)
                Text("暗色").tag(AppAppearance.dark)
            }
            .pickerStyle(.segmented)
            colorPicker("冲突 / 阻塞", hex: changeColourBinding(.conflicted))
            colorPicker("新增", hex: changeColourBinding(.added))
            colorPicker("删除 / 缺失 / 替换", hex: changeColourBinding(.deleted))
            colorPicker("已合并", hex: changeColourBinding(.merged))
            colorPicker("修改 / 复制", hex: changeColourBinding(.modified))
            Button("恢复状态色默认值") {
                changeColours = ChangeColourPalette()
            }
        }
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
        Section("HTTP 代理") {
            Toggle("启用 HTTP 代理", isOn: $networkPreferences.proxy.enabled)
            TextField("代理主机", text: $networkPreferences.proxy.host)
                .disabled(!networkPreferences.proxy.enabled)
            Stepper(
                "端口 \(networkPreferences.proxy.port)",
                value: $networkPreferences.proxy.port,
                in: 1...65_535
            )
            .disabled(!networkPreferences.proxy.enabled)
            TextField("例外（逗号分隔）", text: proxyExceptionsBinding())
                .disabled(!networkPreferences.proxy.enabled)
            TextField("代理用户名", text: $networkPreferences.proxy.username)
                .disabled(!networkPreferences.proxy.enabled)
            SecureField("代理密码", text: $proxyPassword)
                .disabled(!networkPreferences.proxy.enabled)
        }
        Section("SSH 客户端") {
            HStack {
                TextField("可执行路径（留空使用系统 OpenSSH）", text: optionalStringBinding($networkPreferences.sshExecutablePath))
                Button {
                    chooseExecutable(for: optionalStringBinding($networkPreferences.sshExecutablePath))
                } label: {
                    Image(systemName: "doc.badge.gearshape")
                }
                .help("选择 SSH 客户端")
            }
            patternEditor("SSH 参数（每行一个）", text: sshArgumentsBinding())
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
                        Text(LocalizedStringKey(type.displayName)).tag(type)
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
                    Text(LocalizedStringKey(mode.displayName)).tag(mode)
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
                    Toggle(isOn: finderSyncBadgeBinding(badge)) {
                        Text(LocalizedStringKey(badge.displayName))
                    }
                }
            }
        }
        Section("Finder 菜单") {
            DisclosureGroup("提升到顶层的命令") {
                ForEach(SvnCommandCatalog.dailyCFMCommands, id: \.id) { descriptor in
                    Toggle(isOn: finderSyncPromotedCommandBinding(descriptor.id)) {
                        Text(LocalizedStringKey(descriptor.displayName))
                    }
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
        guard baselineDraft == nil else { return }
        await loadSettings()
    }

    private func reloadSettings() async {
        guard !isLoading, !isSaving, !hasUnsavedChanges else { return }
        await loadSettings()
    }

    private func loadSettings() async {
        isLoading = true
        defer { isLoading = false }
        feedback = nil
        var loadFeedback: MacSvnAuxiliaryFeedback?
        let settings = await session.settingsStore.settings()
        guard !Task.isCancelled else { return }
        generalPreferences = settings.general
        dialogPreferences = settings.dialogs
        changeColours = settings.changeColours
        networkPreferences = settings.network
        do {
            let managed = try session.svnClientConfigurationStore.load()
            globalIgnorePatterns = managed.globalIgnorePatterns.joined(separator: "\n")
            useCommitTimes = managed.useCommitTimes
            networkPreferences = managed.network
            proxyPassword = managed.proxyPassword
        } catch {
            navigateToSettingsCategory(MacSvnSettingsErrorPresentation.category(for: error))
            let diagnostic = error.localizedDescription
            loadFeedback = MacSvnAuxiliaryFeedback.localized(
                kind: .warning,
                message: "读取 SVN config/servers 失败：\(MacSvnAuxiliaryErrorSummaryPresentation.message(diagnostic, locale: locale))",
                locale: locale,
                diagnostic: diagnostic
            )
        }
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
        baselineDraft = currentDraft
        feedback = loadFeedback
    }

    private func save() async {
        guard !isSaving else { return }
        guard hasUnsavedChanges else { return }
        let draftBeingSaved = currentDraft
        isSaving = true
        feedback = nil
        defer { isSaving = false }

        if let invalidHook = clientHooks.first(where: {
            $0.isEnabled && (
                $0.workingCopyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || $0.executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }) {
            navigateToSettingsCategory(.savedData)
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .failure,
                message: "无法保存：\(invalidHook.type.displayName) 钩子需要工作副本路径和脚本路径。",
                locale: locale,
                diagnostic: nil
            )
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
        settings.general = generalPreferences
        settings.dialogs = dialogPreferences
        settings.changeColours = changeColours
        settings.network = networkPreferences
        var nextManaged: SvnClientManagedConfiguration
        do {
            nextManaged = try session.svnClientConfigurationStore.load()
        } catch {
            navigateToSettingsCategory(MacSvnSettingsErrorPresentation.category(for: error))
            let diagnostic = error.localizedDescription
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .failure,
                message: "保存失败：\(MacSvnAuxiliaryErrorSummaryPresentation.message(diagnostic, locale: locale))",
                locale: locale,
                diagnostic: diagnostic
            )
            return
        }
        nextManaged.globalIgnorePatterns = globalIgnoreTokens(from: globalIgnorePatterns)
        nextManaged.useCommitTimes = useCommitTimes
        nextManaged.network = networkPreferences
        nextManaged.proxyPassword = proxyPassword
        do {
            try await TortoiseParitySettingsPersistenceCoordinator(
                settingsStore: session.settingsStore,
                historyStore: session.commitMessageHistoryStore,
                configurationStore: session.svnClientConfigurationStore
            ).save(
                settings: settings,
                managedConfiguration: nextManaged
            )
            session.publish(settings: settings)
        } catch {
            navigateToSettingsCategory(MacSvnSettingsErrorPresentation.category(for: error))
            let diagnostic = error.localizedDescription
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .failure,
                message: "保存失败：\(MacSvnAuxiliaryErrorSummaryPresentation.message(diagnostic, locale: locale))",
                locale: locale,
                diagnostic: diagnostic
            )
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
            let diagnostic = error.localizedDescription
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .warning,
                message: "设置已保存，但 Finder 扩展配置同步失败：\(MacSvnAuxiliaryErrorSummaryPresentation.message(diagnostic, locale: locale))",
                locale: locale,
                diagnostic: diagnostic
            )
            return
        }
        baselineDraft = draftBeingSaved
        feedback = MacSvnAuxiliaryFeedback.localized(
            kind: .success,
            message: "已保存。界面、对话框、状态色和 SVN 网络配置已更新；svn 路径与客户端钩子将在下次启动会话后完全生效。",
            locale: locale,
            diagnostic: nil
        )
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch session.updateStatus {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
        case .upToDate(let version):
            Text("当前已是最新版本 \(version)").foregroundStyle(.secondary)
        case .updateAvailable(let release):
            Link("发现版本 \(release.version)", destination: release.pageURL)
        case .failed(let message):
            Text("检查失败：\(message)").foregroundStyle(.red)
        }
    }

    private func openSvnConfig() {
        do {
            try session.svnClientConfigurationStore.ensureFilesExist()
            NSWorkspace.shared.open(session.svnClientConfigurationStore.configFileURL)
        } catch {
            let diagnostic = error.localizedDescription
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .failure,
                message: "无法打开 SVN config：\(MacSvnAuxiliaryErrorSummaryPresentation.message(diagnostic, locale: locale))",
                locale: locale,
                diagnostic: diagnostic
            )
        }
    }

    private func openSvnServers() {
        do {
            try session.svnClientConfigurationStore.ensureFilesExist()
            NSWorkspace.shared.open(session.svnClientConfigurationStore.serversFileURL)
        } catch {
            let diagnostic = error.localizedDescription
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .failure,
                message: "无法打开 SVN servers：\(MacSvnAuxiliaryErrorSummaryPresentation.message(diagnostic, locale: locale))",
                locale: locale,
                diagnostic: diagnostic
            )
        }
    }

    @ViewBuilder
    private func externalToolRuleEditor(_ rule: Binding<ExternalToolRule>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("用途", selection: rule.purpose) {
                    ForEach(ExternalToolPurpose.allCases) { purpose in
                        Text(LocalizedStringKey(purpose.displayName)).tag(purpose)
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
                navigateToSettingsCategory(.externalPrograms)
                feedback = MacSvnAuxiliaryFeedback.localized(
                    kind: .failure,
                    message: "无法保存：外置工具规则需要名称和可执行路径。",
                    locale: locale,
                    diagnostic: nil
                )
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
                    navigateToSettingsCategory(.externalPrograms)
                    feedback = MacSvnAuxiliaryFeedback.localized(
                        kind: .failure,
                        message: "无法保存：同一用途不能重复配置扩展名 \(key)。",
                        locale: locale,
                        diagnostic: nil
                    )
                    return nil
                }
            }
            normalized.append(copy)
        }
        return normalized
    }

    private func navigateToSettingsCategory(_ category: MacSvnSettingsCategory?) {
        guard let category else { return }
        settingsSearchText = ""
        selectedCategory = category
    }

    private func clearLogCache() async {
        guard !isClearingLogCache else { return }
        isClearingLogCache = true
        defer { isClearingLogCache = false }
        do {
            try await session.logCacheStore.clearAll()
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .success,
                message: "日志缓存已清理。",
                locale: locale,
                diagnostic: nil
            )
        } catch {
            let diagnostic = error.localizedDescription
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .failure,
                message: "清理日志缓存失败：\(MacSvnAuxiliaryErrorSummaryPresentation.message(diagnostic, locale: locale))",
                locale: locale,
                diagnostic: diagnostic
            )
        }
    }

    private func clearAuthenticationCache() async {
        guard !isClearingAuthenticationCache else { return }
        isClearingAuthenticationCache = true
        defer { isClearingAuthenticationCache = false }
        do {
            let result = try await session.svnAuthenticationCacheStore.clearAll()
            if result.removedFileCacheItemCount == 0 {
                feedback = MacSvnAuxiliaryFeedback.localized(
                    kind: .success,
                    message: "已完成 Subversion 认证缓存清理。",
                    locale: locale,
                    diagnostic: nil
                )
            } else {
                feedback = MacSvnAuxiliaryFeedback.localized(
                    kind: .success,
                    message: "已完成 Subversion 认证缓存清理（移除 \(result.removedFileCacheItemCount) 项文件缓存）。",
                    locale: locale,
                    diagnostic: nil
                )
            }
        } catch {
            let diagnostic = error.localizedDescription
            feedback = MacSvnAuxiliaryFeedback.localized(
                kind: .failure,
                message: "清理 Subversion 认证缓存失败：\(MacSvnAuxiliaryErrorSummaryPresentation.message(diagnostic, locale: locale))",
                locale: locale,
                diagnostic: diagnostic
            )
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

    private func globalIgnoreTokens(from text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private func optionalStringBinding(_ value: Binding<String?>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue ?? "" },
            set: {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                value.wrappedValue = trimmed.isEmpty ? nil : $0
            }
        )
    }

    private func proxyExceptionsBinding() -> Binding<String> {
        Binding(
            get: { networkPreferences.proxy.exceptions.joined(separator: ", ") },
            set: { text in
                networkPreferences.proxy.exceptions = text
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private func sshArgumentsBinding() -> Binding<String> {
        Binding(
            get: { networkPreferences.sshArguments.joined(separator: "\n") },
            set: { networkPreferences.sshArguments = patterns(from: $0) }
        )
    }

    private func changeColourBinding(_ role: ChangeColourRole) -> Binding<String> {
        Binding(
            get: { changeColours.hex(for: role, appearance: colourAppearance) },
            set: { newValue in
                let current = changeColours.colour(for: role)
                let updated = AdaptiveColour(
                    lightHex: colourAppearance == .light ? newValue : current.lightHex,
                    darkHex: colourAppearance == .dark ? newValue : current.darkHex,
                    fallback: current
                )
                switch role {
                case .modified: changeColours.modified = updated
                case .added: changeColours.added = updated
                case .deleted: changeColours.deleted = updated
                case .merged: changeColours.merged = updated
                case .conflicted: changeColours.conflicted = updated
                }
            }
        )
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
