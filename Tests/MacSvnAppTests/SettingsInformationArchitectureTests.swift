import Foundation
import XCTest
@testable import MacSvnApp
import MacSvnCore

final class SettingsInformationArchitectureTests: XCTestCase {
    func testSettingsCategoryModelKeepsRequiredCategoriesAndTitlesInStableOrder() {
        XCTAssertEqual(
            MacSvnSettingsCategory.allCases,
            [.general, .dialogs, .colours, .network, .externalPrograms, .savedData,
             .finder, .revisionGraph, .ai]
        )
        XCTAssertEqual(
            MacSvnSettingsCategory.allCases.map(\.title),
            ["General", "Dialogs", "Colours", "Network", "External Programs", "Saved Data",
             "Finder", "Revision Graph", "AI"]
        )
        XCTAssertTrue(MacSvnSettingsCategory.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }

    func testSettingsCategoriesMatchHumanSearchTerms() {
        XCTAssertTrue(MacSvnSettingsCategory.network.matches(search: "代理"))
        XCTAssertTrue(MacSvnSettingsCategory.network.matches(search: "  PROXY  "))
        XCTAssertTrue(MacSvnSettingsCategory.savedData.matches(search: "cache"))
        XCTAssertTrue(MacSvnSettingsCategory.externalPrograms.matches(search: "合并工具"))
        XCTAssertTrue(MacSvnSettingsCategory.revisionGraph.matches(search: "branch graph"))
        XCTAssertTrue(MacSvnSettingsCategory.ai.matches(search: "provider"))
        XCTAssertTrue(MacSvnSettingsCategory.general.matches(search: ""))
        XCTAssertFalse(MacSvnSettingsCategory.ai.matches(search: "锁定"))
    }

    func testSettingsConfigurationErrorsPointToOwnedCategory() {
        XCTAssertEqual(
            MacSvnSettingsErrorPresentation.category(
                for: SvnClientConfigurationError.invalidValue("global-ignores")
            ),
            .general
        )
        XCTAssertEqual(
            MacSvnSettingsErrorPresentation.category(
                for: SvnClientConfigurationError.invalidValue("use-commit-times")
            ),
            .general
        )
        XCTAssertEqual(
            MacSvnSettingsErrorPresentation.category(
                for: SvnClientConfigurationError.invalidValue("http-proxy-host")
            ),
            .network
        )
        XCTAssertEqual(
            MacSvnSettingsErrorPresentation.category(
                for: SvnClientConfigurationError.invalidProxyPort(0)
            ),
            .network
        )
        XCTAssertNil(
            MacSvnSettingsErrorPresentation.category(
                for: NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError)
            )
        )
    }

    func testSettingsBaselineAdvancesOnlyAfterFinderSyncCompletes() throws {
        let source = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnSettingsView.swift"
        )
        let save = try Self.sourceSection(
            source,
            from: "private func save()",
            to: "private func clearLogCache()"
        )
        let finderExport = try XCTUnwrap(save.range(of: "FinderSyncRootsExporter.export("))
        let baselineAdvance = try XCTUnwrap(save.range(of: "baselineDraft = draftBeingSaved"))

        XCTAssertLessThan(finderExport.lowerBound, baselineAdvance.lowerBound)
    }

    func testSettingsLoadingBlocksEditingAndCannotOverwriteAnExistingDraft() throws {
        let source = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnSettingsView.swift"
        )
        let load = try Self.sourceSection(source, from: "private func load()", to: "private func save()")

        XCTAssertTrue(source.contains(".disabled(isLoading || isSaving)"))
        XCTAssertTrue(load.contains("guard baselineDraft == nil else { return }"))
        XCTAssertTrue(load.contains("guard !Task.isCancelled else { return }"))
    }

    func testSettingsPageProvidesTortoiseParityCategoryNavigation() throws {
        let source = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnSettingsView.swift"
        )

        XCTAssertTrue(source.contains("@State private var selectedCategory: MacSvnSettingsCategory? = .general"))
        XCTAssertTrue(source.contains("List(selection: $selectedCategory)"))
        XCTAssertTrue(source.contains("ForEach(filteredCategories)"))
        XCTAssertTrue(source.contains(".tag(category)"))
        for category in [
            "case .general:",
            "case .dialogs:",
            "case .colours:",
            "case .network:",
            "case .externalPrograms:",
            "case .savedData:",
            "case .finder:",
            "case .revisionGraph:",
            "case .ai:",
        ] {
            XCTAssertTrue(source.contains(category), "missing settings category branch: \(category)")
        }
    }

    func testSettingsPageKeepsExistingLoadAndSaveMappings() throws {
        let source = try Self.readRepoSource(at: "Sources/MacSvnApp/Features/MacSvnSettingsView.swift")
        let load = try Self.sourceSection(source, from: "private func load()", to: "private func save()")
        let save = try Self.sourceSection(source, from: "private func save()", to: "private func clearLogCache()")

        let mappings = [
            ("svnPath", "settings.svnPath"),
            ("logBatchSize", "settings.logBatchSize"),
            ("processTimeout", "settings.processTimeout"),
            ("progressAutoCloseMode", "settings.progressAutoCloseMode"),
            ("shelvingVersion", "settings.shelvingVersion"),
            ("logCacheEnabled", "settings.logCachePolicy"),
            ("logCacheRetentionDays", "settings.logCachePolicy"),
            ("logCacheMaxEntries", "settings.logCachePolicy"),
            ("clientHooks", "settings.clientHooks"),
            ("finderSyncCacheMode", "settings.finderSyncCacheMode"),
            ("finderSyncIncludedPaths", "settings.finderSyncOverlaySettings"),
            ("finderSyncExcludedPaths", "settings.finderSyncOverlaySettings"),
            ("finderSyncEnabledBadges", "settings.finderSyncOverlaySettings"),
            ("finderSyncPromotedCommandIDs", "settings.finderSyncContextMenuSettings"),
            ("finderSyncPromoteLockForNeedsLock", "settings.finderSyncContextMenuSettings"),
            ("finderSyncHideUnversionedMenus", "settings.finderSyncContextMenuSettings"),
            ("finderSyncMenuExcludedPaths", "settings.finderSyncContextMenuSettings"),
            ("hardBlockConflictMarkers", "settings.commitGuardHardBlockConflictMarkers"),
            ("trunk", "settings.branchLayout"),
            ("branches", "settings.branchLayout"),
            ("tags", "settings.branchLayout"),
            ("graphTrunkPatterns", "settings.revisionGraph"),
            ("graphBranchPatterns", "settings.revisionGraph"),
            ("graphTagPatterns", "settings.revisionGraph"),
            ("graphBlendCopyColors", "settings.revisionGraph"),
            ("graphTrunkHex", "settings.revisionGraph"),
            ("graphBranchHex", "settings.revisionGraph"),
            ("graphTagHex", "settings.revisionGraph"),
            ("graphUnclassifiedHex", "settings.revisionGraph"),
            ("externalDiffName", "settings.externalDiffTool"),
            ("externalDiffPath", "settings.externalDiffTool"),
        ]
        for (state, setting) in mappings {
            XCTAssertTrue(load.contains(state), "load no longer maps \(state)")
            XCTAssertTrue(load.contains(setting), "load no longer reads \(setting)")
            XCTAssertTrue(save.contains(state), "save no longer maps \(state)")
            XCTAssertTrue(save.contains(setting), "save no longer writes \(setting)")
        }
    }

    func testSavedDataKeepsAuthenticationAndLogCacheCleanupAvailable() throws {
        let source = try Self.readRepoSource(at: "Sources/MacSvnApp/Features/MacSvnSettingsView.swift")

        XCTAssertTrue(source.contains("Section(\"认证缓存\")"))
        XCTAssertTrue(source.contains("Button(\"清除 Subversion 认证缓存…\", role: .destructive)"))
        XCTAssertTrue(source.contains("清除 Subversion 认证缓存？"))
        XCTAssertTrue(source.contains("session.svnAuthenticationCacheStore.clearAll()"))
        XCTAssertTrue(source.contains("auth 文件和 Keychain 凭据"))
        XCTAssertTrue(source.contains("不会删除 AI Provider 凭据。"))
        XCTAssertTrue(source.contains("Button(\"清理全部日志缓存\")"))
        XCTAssertTrue(source.contains("session.logCacheStore.clearAll()"))
    }

    func testExternalProgramRulesReachSettingsDiffMergeAndBlameWorkflows() throws {
        let settings = try Self.readRepoSource(at: "Sources/MacSvnApp/Features/MacSvnSettingsView.swift")
        let diff = try Self.readRepoSource(at: "Sources/MacSvnApp/Features/MacSvnDiffView.swift")
        let conflicts = try Self.readRepoSource(at: "Sources/MacSvnApp/Features/MacSvnConflictWorkspaceView.swift")
        let blame = try Self.readRepoSource(at: "Sources/MacSvnApp/Features/MacSvnBlameView.swift")

        XCTAssertTrue(settings.contains("externalToolRules"))
        XCTAssertTrue(settings.contains("ExternalToolPurpose.allCases"))
        XCTAssertTrue(settings.contains("settings.externalToolRules"))
        XCTAssertTrue(settings.contains("externalDiffArguments"))
        XCTAssertTrue(diff.contains("ExternalToolRuleResolver.tool("))
        XCTAssertTrue(diff.contains("for: .diff"))
        XCTAssertTrue(conflicts.contains("外置 Merge"))
        XCTAssertTrue(conflicts.contains("for: .merge"))
        XCTAssertTrue(conflicts.contains("ExternalToolLaunchService"))
        XCTAssertTrue(blame.contains("外置 Blame"))
        XCTAssertTrue(blame.contains("for: .blame"))
        XCTAssertTrue(blame.contains("ExternalToolLaunchService"))
    }

    func testTortoiseParitySettingsLoadSaveAndSynchronizeSvnConfiguration() throws {
        let source = try Self.readRepoSource(at: "Sources/MacSvnApp/Features/MacSvnSettingsView.swift")
        let coordinator = try Self.readRepoSource(
            at: "Sources/MacSvnApp/App/TortoiseParitySettingsPersistenceCoordinator.swift"
        )
        let load = try Self.sourceSection(source, from: "private func load()", to: "private func save()")
        let save = try Self.sourceSection(source, from: "private func save()", to: "private func clearLogCache()")
        let mappings = [
            ("generalPreferences", "settings.general", "settings.general"),
            ("dialogPreferences", "settings.dialogs", "settings.dialogs"),
            ("changeColours", "settings.changeColours", "settings.changeColours"),
            ("networkPreferences", "settings.network", "settings.network"),
            ("globalIgnorePatterns", "managed.globalIgnorePatterns", "nextManaged.globalIgnorePatterns"),
            ("useCommitTimes", "managed.useCommitTimes", "nextManaged.useCommitTimes"),
        ]
        for (state, loadSetting, saveSetting) in mappings {
            XCTAssertTrue(load.contains(state), "load no longer maps \(state)")
            XCTAssertTrue(load.contains(loadSetting), "load no longer reads \(loadSetting)")
            XCTAssertTrue(save.contains(state), "save no longer maps \(state)")
            XCTAssertTrue(save.contains(saveSetting), "save no longer writes \(saveSetting)")
        }

        for label in [
            "界面语言", "自动检查更新", "Global ignore", "使用最后提交时间",
            "应用本地修改的 svn:externals", "日志字体", "短日期/时间",
            "双击日志修订时与前一修订比较", "还原前移到废纸篓", "默认 Checkout 路径",
            "递归显示未版本目录", "提交说明自动完成", "提交说明历史",
            "自动勾选版本化修改", "提交后仍有改动时重开", "启动时联系仓库",
            "获取锁前显示对话框", "预取仓库子目录", "显示 svn:externals",
            "亮色", "暗色", "HTTP 代理", "代理密码", "SSH 客户端",
        ] {
            XCTAssertTrue(source.contains(label), "missing Tortoise parity setting: \(label)")
        }
        XCTAssertTrue(source.contains("session.svnClientConfigurationStore.load()"))
        XCTAssertTrue(source.contains("TortoiseParitySettingsPersistenceCoordinator("))
        XCTAssertTrue(coordinator.contains("configurationStore.update(managedConfiguration)"))
        XCTAssertTrue(coordinator.contains("configurationStore.update(originalConfiguration)"))
        XCTAssertTrue(source.contains("session.publish(settings: settings)"))
        XCTAssertTrue(source.contains("session.checkForUpdates()"))
        XCTAssertTrue(source.contains("NSWorkspace.shared.open(session.svnClientConfigurationStore.configFileURL)"))
        XCTAssertTrue(source.contains("NSWorkspace.shared.open(session.svnClientConfigurationStore.serversFileURL)"))
        XCTAssertTrue(source.contains("networkPreferences = managed.network"))
        XCTAssertFalse(source.contains("managed.network != SvnNetworkSettings()"))
        XCTAssertTrue(source.contains("session.svnClientConfigurationStore.ensureFilesExist()"))
        XCTAssertFalse(source.contains("private func synchronizeSvnConfigFiles()"))
    }

    func testDesktopAppObservesSessionWhenApplyingSelectedLanguageLocale() throws {
        let source = try Self.readRepoSource(
            at: "Sources/MacSvnDesktopApp/MacSvnDesktopApp.swift"
        )

        XCTAssertTrue(source.contains("struct MacSvnLocalizedSessionView: View"))
        XCTAssertTrue(source.contains("@ObservedObject var session: MacSvnAppSession"))
        XCTAssertTrue(source.contains("struct MacSvnLocalizedContent<Content: View>: View"))
        XCTAssertTrue(source.contains(".environment(\\.locale, selectedLocale)"))
    }

    func testCommitEditorConsumesAutoCompletionAndRevertSafetySettings() throws {
        let commit = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnCommitView.swift"
        )
        let editor = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/BugtraqIssueTextEditor.swift"
        )

        XCTAssertTrue(commit.contains("dialogs.enableCommitAutoCompletion"))
        let completionBuilder = try Self.sourceSection(
            commit,
            from: "private func rebuildCompletionCandidates(",
            to: "private func diffSelected"
        )
        XCTAssertTrue(completionBuilder.contains("autoCompletionTimeoutSeconds"))
        XCTAssertTrue(completionBuilder.contains("candidateStatuses.map(\\.path)"))
        XCTAssertTrue(completionBuilder.contains("recentMessages"))
        XCTAssertTrue(commit.contains("useTrashWhenReverting: settings.dialogs.useTrashWhenReverting"))
        XCTAssertTrue(commit.contains("@State private var completionCandidates: [String] = []"))
        XCTAssertTrue(commit.contains("Task.detached(priority: .utility)"))
        let messagePanel = try Self.sourceSection(
            commit,
            from: "private func messagePanel(_ viewModel: CommitViewModel)",
            to: "private func projectPropertyPanel"
        )
        XCTAssertFalse(messagePanel.contains("CommitMessageCompletionCandidates.build"))
        XCTAssertTrue(editor.contains("textView.isAutomaticTextCompletionEnabled"))
        XCTAssertTrue(editor.contains("completionIndex.matches"))
        XCTAssertTrue(editor.contains("CommitMessageCompletionIndex"))
        XCTAssertTrue(editor.contains("maxCandidates: Int = 512"))
        XCTAssertTrue(editor.contains("maxResults: Int = 20"))
        XCTAssertTrue(commit.contains("viewModel?.updateSettings("))
        let changes = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnChangesView.swift"
        )
        XCTAssertTrue(changes.contains(".onChange(of: session.settingsSnapshot.dialogs)"))
        XCTAssertTrue(changes.contains("changesVM?.updateSettings("))
        XCTAssertTrue(changes.contains("actionsVM?.updateSettings("))
    }

    func testChangeColourPaletteIsConsumedByAllStatusWorkflows() throws {
        for path in [
            "Sources/MacSvnApp/Features/MacSvnChangesView.swift",
            "Sources/MacSvnApp/Features/MacSvnDiffView.swift",
            "Sources/MacSvnApp/Features/MacSvnLogView.swift",
            "Sources/MacSvnApp/Features/MacSvnMergeWizardView.swift",
            "Sources/MacSvnApp/Features/MacSvnConflictWorkspaceView.swift",
        ] {
            let source = try Self.readRepoSource(at: path)
            XCTAssertTrue(source.contains("settingsSnapshot.changeColours"), "missing palette in \(path)")
            XCTAssertTrue(source.contains("svnChangeColour("), "missing resolver in \(path)")
        }
    }

    private static func readRepoSource(at path: String) throws -> String {
        let testsFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testsFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repoRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static func sourceSection(
        _ source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return source[start..<end]
    }
}
