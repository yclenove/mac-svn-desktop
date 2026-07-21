import Foundation
import XCTest
@testable import MacSvnApp
import MacSvnCore

final class HumanCenteredAuxiliaryWorkflowsTests: XCTestCase {
    func testAuxiliaryFeedbackPreservesSemanticKindMessageAndDiagnostic() {
        XCTAssertEqual(
            MacSvnAuxiliaryFeedback(
                kind: .failure,
                message: "无法连接到仓库",
                diagnostic: "E170013: unable to connect"
            ),
            MacSvnAuxiliaryFeedback(
                kind: .failure,
                message: "无法连接到仓库",
                diagnostic: "E170013: unable to connect"
            )
        )
    }

    func testAuxiliaryFeedbackKindsUseDistinctIconsAndColorRoles() {
        let kinds: [MacSvnAuxiliaryFeedbackKind] = [
            .progress,
            .success,
            .warning,
            .failure,
        ]

        for firstIndex in kinds.indices {
            for secondIndex in kinds.indices where firstIndex < secondIndex {
                XCTAssertNotEqual(
                    kinds[firstIndex].systemImage,
                    kinds[secondIndex].systemImage
                )
                XCTAssertNotEqual(
                    kinds[firstIndex].colorRole,
                    kinds[secondIndex].colorRole
                )
            }
        }
    }

    func testAuxiliaryFeedbackLocalizedConstructorFormatsDynamicEnglishResource() throws {
        let diagnostic = "E170013: unable to connect"
        let locale = Locale(identifier: "en")
        let bundle = LocalizedStringResource.BundleDescription.atURL(Self.desktopResourcesRoot)

        let feedback = MacSvnAuxiliaryFeedback.localized(
            kind: .failure,
            message: "属性操作失败：\(diagnostic)",
            locale: locale,
            bundle: bundle,
            diagnostic: diagnostic
        )

        XCTAssertEqual(feedback.message, "Property operation failed: \(diagnostic)")
        XCTAssertEqual(feedback.diagnostic, diagnostic)
    }

    func testAuxiliaryFeedbackLocalizesCoreErrorSummaryBeforeOuterEnglishFormat() {
        let locale = Locale(identifier: "en")
        let bundle = LocalizedStringResource.BundleDescription.atURL(Self.desktopResourcesRoot)
        let raw = "svn: E170013: Unable to connect to a repository at URL"
        let summary = MacSvnAuxiliaryErrorSummaryPresentation.message(
            raw,
            locale: locale,
            bundle: bundle
        )
        let feedback = MacSvnAuxiliaryFeedback.localized(
            kind: .failure,
            message: "属性操作失败：\(summary)",
            locale: locale,
            bundle: bundle,
            diagnostic: raw
        )

        XCTAssertEqual(
            feedback.message,
            "Property operation failed: Unable to connect to the repository. Check the network and repository URL, then try again."
        )
        XCTAssertFalse(feedback.message.contains("无法连接"))
        XCTAssertEqual(feedback.diagnostic, raw)
    }

    func testNewAuxiliaryFeedbackFormatsHaveEnglishResources() {
        let locale = Locale(identifier: "en")
        let bundle = LocalizedStringResource.BundleDescription.atURL(Self.desktopResourcesRoot)
        let info = "info failed"
        let status = "status failed"
        let detail = "operation failed"

        let expectations: [(LocalizedStringResource, String)] = [
            (
                LocalizedStringResource(
                    "SVN 信息与状态读取失败：\(info)；\(status)",
                    locale: locale,
                    bundle: bundle
                ),
                "Failed to read SVN info and status: \(info); \(status)"
            ),
            (
                LocalizedStringResource("锁操作失败：\(detail)", locale: locale, bundle: bundle),
                "Lock operation failed: \(detail)"
            ),
            (
                LocalizedStringResource("等待确认夺锁：\(2) 项", locale: locale, bundle: bundle),
                "Awaiting confirmation to steal locks: 2 items"
            ),
            (
                LocalizedStringResource("等待确认打断锁：\(3) 项", locale: locale, bundle: bundle),
                "Awaiting confirmation to break locks: 3 items"
            ),
            (
                LocalizedStringResource("锁记录 \(4)", locale: locale, bundle: bundle),
                "4 lock records"
            ),
            (
                LocalizedStringResource("搁置操作失败：\(detail)", locale: locale, bundle: bundle),
                "Shelf operation failed: \(detail)"
            ),
            (
                LocalizedStringResource("外部定义读取失败：\(detail)", locale: locale, bundle: bundle),
                "Failed to read external definitions: \(detail)"
            ),
            (
                LocalizedStringResource("外部定义操作失败：\(detail)", locale: locale, bundle: bundle),
                "External definition operation failed: \(detail)"
            ),
            (
                LocalizedStringResource("已加载 \(detail) 的版本记录", locale: locale, bundle: bundle),
                "Loaded version history for \(detail)"
            ),
            (
                LocalizedStringResource("已加载 \(detail) 的 Diff", locale: locale, bundle: bundle),
                "Loaded diff for \(detail)"
            ),
            (
                LocalizedStringResource("已加载 \(detail) 的本地 Patch", locale: locale, bundle: bundle),
                "Loaded local patch for \(detail)"
            ),
            (
                LocalizedStringResource("已恢复 \(detail)", locale: locale, bundle: bundle),
                "Restored \(detail)"
            ),
            (
                LocalizedStringResource("已恢复 \(detail) 并删除 shelf", locale: locale, bundle: bundle),
                "Restored \(detail) and dropped the shelf"
            ),
            (
                LocalizedStringResource("已删除官方 shelf \(detail)", locale: locale, bundle: bundle),
                "Deleted official shelf \(detail)"
            ),
            (
                LocalizedStringResource("已删除本地快照 \(detail)", locale: locale, bundle: bundle),
                "Deleted local snapshot \(detail)"
            ),
            (
                LocalizedStringResource("已将 \(detail) 迁移到官方 shelf", locale: locale, bundle: bundle),
                "Migrated \(detail) to an official shelf"
            ),
            (
                LocalizedStringResource(
                    "已完成 Subversion 认证缓存清理（移除 \(5) 项文件缓存）。",
                    locale: locale,
                    bundle: bundle
                ),
                "Subversion authentication cache cleanup completed (removed 5 file cache items)."
            ),
            (
                LocalizedStringResource(
                    "项目属性读取失败，已阻止获取锁。请刷新或重新选择目标后重试。",
                    locale: locale,
                    bundle: bundle
                ),
                "Failed to read project properties, so getting locks is blocked. Refresh or reselect the targets, then try again."
            ),
        ]

        for (resource, expected) in expectations {
            XCTAssertEqual(String(localized: resource), expected)
        }
    }

    func testPropertyLoadFeedbackKeepsPrimaryFailureAboveSupplementalWarnings() throws {
        let feedback = try XCTUnwrap(MacSvnPropertyLoadFeedbackPresentation.feedback(
            propertyState: .error("SSL certificate verification failed"),
            infoDiagnostic: "E170013: unable to connect",
            statusDiagnostic: "timed out",
            locale: .current
        ))

        XCTAssertEqual(feedback.kind, .failure)
        XCTAssertEqual(feedback.diagnostic, "SSL certificate verification failed")
        XCTAssertFalse(feedback.message.contains("E170013"))
    }

    func testPropertyLoadFeedbackSurfacesInfoAndStatusFailuresAsWarnings() throws {
        let infoDiagnostic = "E170013: unable to connect"
        let infoFeedback = try XCTUnwrap(MacSvnPropertyLoadFeedbackPresentation.feedback(
            propertyState: .loaded,
            infoDiagnostic: infoDiagnostic,
            statusDiagnostic: nil,
            locale: .current
        ))
        XCTAssertEqual(infoFeedback.kind, .warning)
        XCTAssertEqual(infoFeedback.diagnostic, infoDiagnostic)
        XCTAssertFalse(infoFeedback.message.contains("E170013"))

        let statusDiagnostic = "Process timed out after 120 seconds."
        let statusFeedback = try XCTUnwrap(MacSvnPropertyLoadFeedbackPresentation.feedback(
            propertyState: .loaded,
            infoDiagnostic: nil,
            statusDiagnostic: statusDiagnostic,
            locale: .current
        ))
        XCTAssertEqual(statusFeedback.kind, .warning)
        XCTAssertEqual(statusFeedback.diagnostic, statusDiagnostic)
        XCTAssertFalse(statusFeedback.message.contains("120 seconds"))
    }

    func testPropertyLoadFeedbackSurfacesProjectPropertyFailureAndClearsAfterSuccess() throws {
        let projectDiagnostic = "svn: E170013: Unable to connect to repository"
        let projectFeedback = try XCTUnwrap(MacSvnPropertyLoadFeedbackPresentation.feedback(
            propertyState: .loaded,
            infoDiagnostic: nil,
            statusDiagnostic: nil,
            projectPropertyDiagnostic: projectDiagnostic,
            locale: .current
        ))

        XCTAssertEqual(projectFeedback.kind, .warning)
        XCTAssertEqual(projectFeedback.diagnostic, projectDiagnostic)
        XCTAssertFalse(projectFeedback.message.contains("E170013"))
        XCTAssertNil(MacSvnPropertyLoadFeedbackPresentation.feedback(
            propertyState: .loaded,
            infoDiagnostic: nil,
            statusDiagnostic: nil,
            projectPropertyDiagnostic: nil,
            locale: .current
        ))

        let primary = try XCTUnwrap(MacSvnPropertyLoadFeedbackPresentation.feedback(
            propertyState: .error("authentication failed"),
            infoDiagnostic: "info failed",
            statusDiagnostic: "status failed",
            projectPropertyDiagnostic: projectDiagnostic,
            locale: .current
        ))
        XCTAssertEqual(primary.kind, .failure)
        XCTAssertEqual(primary.diagnostic, "authentication failed")
    }

    func testPropertyLoadFeedbackProducesFullyEnglishCoreErrorWithInjectedLocale() throws {
        let locale = Locale(identifier: "en")
        let bundle = LocalizedStringResource.BundleDescription.atURL(Self.desktopResourcesRoot)
        let raw = "svn: E170013: Unable to connect to a repository at URL"
        let feedback = try XCTUnwrap(MacSvnPropertyLoadFeedbackPresentation.feedback(
            propertyState: .error(raw),
            infoDiagnostic: nil,
            statusDiagnostic: nil,
            locale: locale,
            bundle: bundle
        ))

        XCTAssertEqual(
            feedback.message,
            "Property operation failed: Unable to connect to the repository. Check the network and repository URL, then try again."
        )
        for chineseFragment in ["无法", "仓库", "请检查"] {
            XCTAssertFalse(feedback.message.contains(chineseFragment))
        }
        XCTAssertEqual(feedback.diagnostic, raw)
    }

    func testLockFeedbackKeepsProjectPropertyMarkerVisibleAfterSuccessfulLockLoad() throws {
        let marker = "projectPropertiesLoadFailed"
        let diagnostic = "svn: E170013: Unable to connect to repository"
        let feedback = try XCTUnwrap(MacSvnLockFeedbackPresentation.feedback(
            state: .loaded,
            projectPropertyLoadError: marker,
            projectPropertyLoadDiagnostic: diagnostic,
            lockCount: 2,
            fallback: nil,
            locale: .current
        ))

        XCTAssertEqual(feedback.kind, .warning)
        XCTAssertEqual(feedback.diagnostic, diagnostic)
        XCTAssertFalse(feedback.message.contains(marker))
    }

    func testLockFeedbackUsesRawProjectPropertyDiagnosticForMarkerFailure() throws {
        let marker = "projectPropertiesLoadFailed"
        let diagnostic = "svn: E170013: Unable to connect to repository"
        let feedback = try XCTUnwrap(MacSvnLockFeedbackPresentation.feedback(
            state: .error(marker),
            projectPropertyLoadError: marker,
            projectPropertyLoadDiagnostic: diagnostic,
            lockCount: 0,
            fallback: nil,
            locale: .current
        ))

        XCTAssertEqual(feedback.kind, .failure)
        XCTAssertEqual(feedback.diagnostic, diagnostic)
        XCTAssertTrue(feedback.message.contains("项目属性读取失败"))
        XCTAssertFalse(feedback.message.contains(marker))
    }

    func testAuxiliaryDismissalPolicyTruthTable() {
        XCTAssertEqual(
            MacSvnAuxiliaryDismissalPolicy.decision(isBusy: true, isDirty: false),
            .blocked
        )
        XCTAssertEqual(
            MacSvnAuxiliaryDismissalPolicy.decision(isBusy: true, isDirty: true),
            .blocked
        )
        XCTAssertEqual(
            MacSvnAuxiliaryDismissalPolicy.decision(isBusy: false, isDirty: true),
            .confirmDiscard
        )
        XCTAssertEqual(
            MacSvnAuxiliaryDismissalPolicy.decision(isBusy: false, isDirty: false),
            .dismiss
        )
    }

    func testGetLockPresentationPolicyTruthTable() {
        for userPreference in [false, true] {
            for requiresMessage in [false, true] {
                for containsDirectory in [false, true] {
                    XCTAssertEqual(
                        MacSvnGetLockPresentationPolicy.shouldPresent(
                            userPreference: userPreference,
                            requiresMessage: requiresMessage,
                            containsDirectory: containsDirectory
                        ),
                        userPreference || requiresMessage || containsDirectory
                    )
                }
            }
        }
    }

    func testShelveLoadFeedbackMapsInitialOfficialAndLocalFailures() throws {
        let officialDiagnostic = "official unavailable"
        let official = MacSvnShelveFeedbackPresentation.loadFeedback(
            state: .loaded,
            officialError: officialDiagnostic,
            locale: .current
        )
        XCTAssertEqual(official.kind, .warning)
        XCTAssertEqual(official.diagnostic, officialDiagnostic)

        let localDiagnostic = "E170013: unable to connect"
        let local = MacSvnShelveFeedbackPresentation.loadFeedback(
            state: .error(localDiagnostic),
            officialError: officialDiagnostic,
            locale: .current
        )
        XCTAssertEqual(local.kind, .failure)
        XCTAssertEqual(local.diagnostic, localDiagnostic)
        XCTAssertFalse(local.message.contains("E170013"))
    }

    func testShelvePreviewRefreshPolicySkipsLocalFailuresButKeepsValidSelectionForRefreshAndOfficialWarnings() {
        XCTAssertFalse(
            MacSvnShelvePreviewRefreshPolicy.shouldEnqueuePreview(
                after: .localFailure("offline"),
                hasSelection: true
            )
        )
        XCTAssertTrue(
            MacSvnShelvePreviewRefreshPolicy.shouldEnqueuePreview(
                after: .officialFailure("unsupported"),
                hasSelection: true
            )
        )
        XCTAssertTrue(
            MacSvnShelvePreviewRefreshPolicy.shouldEnqueuePreview(
                after: .refreshed,
                hasSelection: true
            )
        )
        XCTAssertFalse(
            MacSvnShelvePreviewRefreshPolicy.shouldEnqueuePreview(
                after: .refreshed,
                hasSelection: false
            )
        )
    }

    func testExternalsPartialSuccessAdvancesBaselineToCommittedDraft() throws {
        let originalDraft = ExternalDefinitionDraft(url: "https://example.test/old", localPath: "old")
        var committedDraft = originalDraft
        committedDraft.url = "https://example.test/new"
        let initial = ExternalsEditorDraftSnapshot(
            drafts: [originalDraft],
            updateAfterSave: true
        )
        let current = ExternalsEditorDraftSnapshot(
            drafts: [committedDraft],
            updateAfterSave: true
        )

        XCTAssertEqual(
            MacSvnExternalsDraftBaselinePolicy.baseline(
                initial: initial,
                current: current,
                outcome: .propertySavedUpdateFailed
            ),
            current
        )
        XCTAssertEqual(
            MacSvnExternalsDraftBaselinePolicy.baseline(
                initial: initial,
                current: current,
                outcome: .failedBeforePropertySave
            ),
            initial
        )
        XCTAssertNil(MacSvnExternalsDraftBaselinePolicy.baseline(
            initial: initial,
            current: current,
            outcome: .completed
        ))
    }

    func testAuxiliaryPagesUseSharedFeedbackAndHumanizeRawErrors() throws {
        let presentation = try Self.readFeatureSource(
            named: "MacSvnAuxiliaryWorkflowPresentation.swift"
        )
        XCTAssertTrue(presentation.contains("struct MacSvnInlineFeedbackView"))
        XCTAssertTrue(presentation.contains(".frame(height: MacSvnAuxiliaryWorkflowMetrics.feedbackHeight)"))
        XCTAssertTrue(presentation.contains(".lineLimit(1)"))
        XCTAssertTrue(presentation.contains(".truncationMode(truncationMode)"))
        XCTAssertTrue(presentation.contains(".help(feedback.diagnostic ?? feedback.message)"))
        XCTAssertTrue(presentation.contains("LocalizedStringResource(\n            message,\n            locale: locale,\n            bundle: bundle"))
        XCTAssertTrue(presentation.contains("String(localized: resource)"))
        XCTAssertTrue(presentation.contains("Text(verbatim: feedback.message)"))
        XCTAssertTrue(presentation.contains("MacSvnCoreModeErrorPresentation.message(rawMessage)"))

        for fileName in [
            "MacSvnPropertiesView.swift",
            "MacSvnLocksView.swift",
            "MacSvnShelveView.swift",
            "MacSvnSettingsView.swift",
        ] {
            let source = try Self.readFeatureSource(named: fileName)
            XCTAssertTrue(
                source.contains("@Environment(\\.locale) private var locale"),
                "\(fileName) must follow MacSvnLocalizedContent's environment locale"
            )
            XCTAssertTrue(source.contains("locale: locale"))
            XCTAssertTrue(
                source.contains("MacSvnInlineFeedbackView("),
                "\(fileName) must render the shared inline feedback view"
            )
            XCTAssertTrue(
                source.contains("MacSvnAuxiliaryErrorSummaryPresentation.message("),
                "\(fileName) must localize authentication, SSL, network, and timeout summaries"
            )
            XCTAssertFalse(source.contains("MacSvnCoreModeErrorPresentation.message("))
            XCTAssertFalse(
                source.contains("MacSvnAuxiliaryFeedback("),
                "\(fileName) must localize feedback before storing its message"
            )
        }
    }

    func testAuxiliaryErrorAndBaselinePoliciesAreWiredIntoPrivateViewState() throws {
        let properties = try Self.readFeatureSource(named: "MacSvnPropertiesView.swift")
        XCTAssertTrue(properties.contains("MacSvnPropertyLoadFeedbackPresentation.feedback("))
        XCTAssertTrue(properties.contains("statusDiagnostic"))
        XCTAssertTrue(properties.contains("projectPropertyDiagnostic"))
        XCTAssertTrue(properties.contains("outcome: .propertySavedUpdateFailed"))

        let loadProperties = try Self.sourceSection(
            startingAt: "private func loadProperties(preservingFeedback: Bool = false) async",
            in: properties
        )
        XCTAssertTrue(loadProperties.contains("do {\n            loadedProjectProperties = try await MacSvnProjectPropertyLoader.load("))
        XCTAssertTrue(loadProperties.contains("propertyLoadFeedback = MacSvnPropertyLoadFeedbackPresentation.feedback("))
        XCTAssertFalse(loadProperties.contains("?? feedback"))

        let locks = try Self.readFeatureSource(named: "MacSvnLocksView.swift")
        XCTAssertTrue(locks.contains("MacSvnLockFeedbackPresentation.feedback("))
        XCTAssertTrue(locks.contains("projectPropertyLoadError: viewModel.projectPropertyLoadError"))
        XCTAssertTrue(locks.contains("projectPropertyLoadDiagnostic: viewModel.projectPropertyLoadDiagnostic"))
        let targetRefresh = try Self.sourceSection(
            startingAt: "private func enqueueTargetRefresh()",
            in: locks
        )
        XCTAssertTrue(targetRefresh.contains("let didApplyProjectProperties = await viewModel.refreshProjectProperties("))
        XCTAssertTrue(targetRefresh.contains("guard didApplyProjectProperties else {\n                await syncStatus()\n                return\n            }"))
        let applyGuard = try XCTUnwrap(targetRefresh.range(of: "guard didApplyProjectProperties else"))
        let lockLoad = try XCTUnwrap(targetRefresh.range(of: "await viewModel.load(targets: lockTargets)"))
        XCTAssertLessThan(applyGuard.lowerBound, lockLoad.lowerBound)

        let shelve = try Self.readFeatureSource(named: "MacSvnShelveView.swift")
        let refreshShelves = try Self.sourceSection(startingAt: "private func refreshShelves()", in: shelve)
        let bootstrap = try Self.sourceSection(startingAt: "private func bootstrap()", in: shelve)
        XCTAssertTrue(refreshShelves.contains("applyShelveLoadFeedback()"))
        XCTAssertTrue(bootstrap.contains("applyShelveLoadFeedback()"))
    }

    func testLockToolbarRefreshUsesFullTargetRefreshPath() throws {
        let locks = try Self.readFeatureSource(named: "MacSvnLocksView.swift")
        let toolbar = try Self.sourceSection(startingAt: "private var locksToolbar", in: locks)
        let request = try Self.sourceSection(startingAt: "private func requestTargetRefresh()", in: locks)

        XCTAssertTrue(toolbar.contains("requestTargetRefresh()"))
        XCTAssertFalse(toolbar.contains("await reload()"))
        XCTAssertTrue(request.contains("enqueueTargetRefresh()"))
    }

    func testPropertiesLoadingClearsActionFeedbackUnlessCallerPreservesIt() throws {
        let properties = try Self.readFeatureSource(named: "MacSvnPropertiesView.swift")
        XCTAssertTrue(properties.contains("private func loadProperties(preservingFeedback: Bool = false) async"))

        let loadProperties = try Self.sourceSection(startingAt: "private func loadProperties(preservingFeedback: Bool = false) async", in: properties)
        XCTAssertTrue(loadProperties.contains("if !preservingFeedback {\n            feedback = nil\n        }"))

        let consumePendingProperty = try Self.sourceSection(startingAt: "private func consumePendingProperty()", in: properties)
        XCTAssertTrue(consumePendingProperty.contains("await loadProperties(preservingFeedback: true)"))

        let saveExternals = try Self.sourceSection(startingAt: "private func saveExternals()", in: properties)
        XCTAssertTrue(saveExternals.contains("await loadProperties(preservingFeedback: true)\n                    return"))
        XCTAssertTrue(saveExternals.contains("await loadProperties()\n            feedback = updateExternalsAfterSave"))
    }

    func testLockSettingsStillAllowDirectGetLockWhenDialogIsNotRequired() throws {
        let source = try Self.readFeatureSource(named: "MacSvnLocksView.swift")
        let section = try Self.sourceSection(startingAt: "private func requestGetLock()", in: source)

        XCTAssertTrue(section.contains("MacSvnGetLockPresentationPolicy.shouldPresent("))
        XCTAssertTrue(section.contains("userPreference: session.settingsSnapshot.dialogs.showLockDialogBeforeLocking"))
        XCTAssertTrue(section.contains("requiresMessage: requiresMessage"))
        XCTAssertTrue(section.contains("containsDirectory: containsDirectory"))
        XCTAssertTrue(section.contains("else {"))
        XCTAssertTrue(section.contains("Task { await runGetLock() }"))
    }

    func testDirtySheetsWireBusyAndDirtyInputsIntoSharedDismissalPolicy() throws {
        let contracts = [
            (
                file: "MacSvnPropertiesView.swift",
                decision: "externalsDismissalDecision",
                busy: "isSavingExternals",
                dirty: "hasUnsavedExternalsChanges",
                request: "requestExternalsDismissal"
            ),
            (
                file: "MacSvnLocksView.swift",
                decision: "getLockDismissalDecision",
                busy: "isBusy",
                dirty: "hasUnsavedGetLockChanges",
                request: "requestGetLockDismissal"
            ),
            (
                file: "MacSvnShelveView.swift",
                decision: "createShelfDismissalDecision",
                busy: "isBusy",
                dirty: "hasUnsavedCreateShelfChanges",
                request: "requestCreateShelfDismissal"
            ),
            (
                file: "MacSvnShelveView.swift",
                decision: "patchDismissalDecision",
                busy: "isPatchBusy",
                dirty: "hasUnsavedPatchChanges",
                request: "requestPatchDismissal"
            ),
        ]

        for contract in contracts {
            let source = try Self.readFeatureSource(named: contract.file)
            XCTAssertTrue(source.contains("MacSvnAuxiliaryDismissalPolicy.decision(\n            isBusy: \(contract.busy),\n            isDirty: \(contract.dirty)"))
            XCTAssertTrue(source.contains("\(contract.decision).preventsDismissal"))
            let request = try Self.sourceSection(
                startingAt: "private func \(contract.request)()",
                in: source
            )
            XCTAssertTrue(request.contains("switch \(contract.decision)"))
            XCTAssertTrue(request.contains("case .blocked:"))
            XCTAssertTrue(request.contains("case .confirmDiscard:"))
            XCTAssertTrue(request.contains("case .dismiss:"))
        }
    }

    func testAsyncSheetDefaultActionsAreDisabledWhileBusy() throws {
        let expectations = [
            ("MacSvnPropertiesView.swift", "private var externalsEditor", "isSavingExternals"),
            ("MacSvnLocksView.swift", "private var getLockSheet", "isBusy"),
            ("MacSvnShelveView.swift", "private var createShelfSheet", "isBusy"),
            ("MacSvnShelveView.swift", "private var patchSheet", "isPatchBusy"),
        ]

        for (fileName, sectionStart, busyState) in expectations {
            let source = try Self.readFeatureSource(named: fileName)
            let section = try Self.sourceSection(startingAt: sectionStart, in: source)
            let shortcutRange = try XCTUnwrap(section.range(of: ".keyboardShortcut(.defaultAction)"))
            let disabledTail = section[shortcutRange.upperBound...].prefix(240)
            XCTAssertTrue(
                disabledTail.contains(".disabled") && disabledTail.contains(busyState),
                "\(fileName) default sheet action must be disabled by \(busyState)"
            )
        }
    }

    func testAuxiliaryMetricsKeepMasterAndDetailReadable() {
        XCTAssertEqual(MacSvnAuxiliaryWorkflowMetrics.toolbarHeight, 48)
        XCTAssertEqual(MacSvnAuxiliaryWorkflowMetrics.masterWidth, 300)
        XCTAssertGreaterThanOrEqual(MacSvnAuxiliaryWorkflowMetrics.masterMinimumWidth, 280)
        XCTAssertLessThanOrEqual(MacSvnAuxiliaryWorkflowMetrics.masterMaximumWidth, 340)
        XCTAssertGreaterThanOrEqual(MacSvnAuxiliaryWorkflowMetrics.detailMinimumWidth, 420)
        XCTAssertEqual(MacSvnAuxiliaryWorkflowMetrics.feedbackHeight, 30)
    }

    func testAuxiliaryPathPresentationOnlyRelativizesTargetsInsideWorkingCopy() {
        let workingCopy = URL(fileURLWithPath: "/tmp/wc", isDirectory: true)

        XCTAssertEqual(
            MacSvnAuxiliaryPathPresentation.relativePath("/tmp/wc", workingCopy: workingCopy),
            "."
        )
        XCTAssertEqual(
            MacSvnAuxiliaryPathPresentation.relativePath(
                "/tmp/wc/src/a.swift",
                workingCopy: workingCopy
            ),
            "src/a.swift"
        )
        XCTAssertEqual(
            MacSvnAuxiliaryPathPresentation.relativePath(
                "/tmp/wc-other/a.swift",
                workingCopy: workingCopy
            ),
            "/tmp/wc-other/a.swift"
        )
        XCTAssertEqual(
            MacSvnAuxiliaryPathPresentation.relativePath("src/a.swift", workingCopy: workingCopy),
            "src/a.swift"
        )
    }

    func testAuxiliaryPathPresentationNamesWorkingCopyRootWithoutExposingDot() {
        XCTAssertEqual(MacSvnAuxiliaryPathPresentation.title(for: "."), "工作副本根目录")
        XCTAssertEqual(MacSvnAuxiliaryPathPresentation.title(for: "src/a.swift"), "src/a.swift")
    }

    func testPropertiesUseSearchableStableMasterDetailAndVisibleEditorAction() throws {
        let source = try Self.readFeatureSource(named: "MacSvnPropertiesView.swift")

        XCTAssertTrue(source.contains("@State private var searchText"))
        XCTAssertTrue(source.contains("@State private var selectedTemplateName"))
        XCTAssertTrue(source.contains("private var propertiesToolbar"))
        XCTAssertTrue(source.contains("private var propertiesWorkspace"))
        XCTAssertTrue(source.contains("private var propertiesMasterPane"))
        XCTAssertTrue(source.contains("private var propertyInspector"))
        XCTAssertTrue(source.contains("private var propertyList"))
        XCTAssertTrue(source.contains("private var propertyEditor"))
        XCTAssertTrue(source.contains("private var propertyEditorActions"))
        XCTAssertTrue(source.contains("Picker(\"模板\", selection: $selectedTemplateName)"))
        XCTAssertTrue(source.contains("HStack(spacing: 0)"))
        XCTAssertTrue(source.contains("MacSvnAuxiliaryWorkflowMetrics.masterWidth"))
        XCTAssertTrue(source.contains(".truncationMode(.middle)"))
        XCTAssertTrue(source.contains("ContentUnavailableView(\"没有属性\""))
        XCTAssertTrue(source.contains(".buttonStyle(.borderedProminent)"))
        XCTAssertTrue(source.contains("MacSvnAuxiliaryPathPresentation.relativePath("))
        XCTAssertFalse(source.contains("HSplitView {"))
        XCTAssertFalse(source.contains("VSplitView {"))
    }

    func testLocksUseTargetMasterDetailAndQualificationDrivenActions() throws {
        let source = try Self.readFeatureSource(named: "MacSvnLocksView.swift")

        XCTAssertTrue(source.contains("@State private var searchText"))
        XCTAssertTrue(source.contains("@State private var isApplyingLockIntent"))
        XCTAssertTrue(source.contains("private var locksToolbar"))
        XCTAssertTrue(source.contains("private var locksFeedback"))
        XCTAssertTrue(source.contains("private var locksWorkspace"))
        XCTAssertTrue(source.contains("private var locksMasterPane"))
        XCTAssertTrue(source.contains("private var lockDetailPane"))
        XCTAssertTrue(source.contains("private var eligibleReleasePaths"))
        XCTAssertTrue(source.contains("private var eligibleBreakPaths"))
        XCTAssertTrue(source.contains("MacSvnAuxiliaryPathList("))
        XCTAssertTrue(source.contains("MacSvnAuxiliaryWorkflowMetrics.masterWidth"))
        XCTAssertTrue(source.contains("ContentUnavailableView(\"没有锁记录\""))
        XCTAssertTrue(source.contains(".buttonStyle(.borderedProminent)"))
        XCTAssertTrue(source.contains("MacSvnLockActionPresentation.eligibleReleasePaths("))
        XCTAssertTrue(source.contains("LockActionPolicy.pathsEligibleForBreak("))
        XCTAssertTrue(source.contains("guard !isApplyingLockIntent else { return }"))
        XCTAssertTrue(source.contains("确认夺锁（svn lock --force）"))
        XCTAssertTrue(source.contains("确认打断锁（svn unlock --force）"))
        XCTAssertFalse(source.contains("HSplitView {"))
        XCTAssertFalse(source.contains("VSplitView {"))
    }

    func testLockActionPresentationRequiresOwnedLockEvidenceBeforeOfferingRelease() {
        let owned = SvnLock(
            target: "owned.txt",
            token: "token",
            owner: "me",
            comment: nil,
            created: nil,
            isOwnedByWorkingCopy: true,
            isRepositoryLocked: true
        )
        let other = SvnLock(
            target: "other.txt",
            token: nil,
            owner: "other",
            comment: nil,
            created: nil,
            isOwnedByWorkingCopy: false,
            isRepositoryLocked: true
        )

        XCTAssertEqual(
            MacSvnLockActionPresentation.eligibleReleasePaths(
                selected: ["owned.txt"],
                locks: []
            ),
            []
        )
        XCTAssertEqual(
            MacSvnLockActionPresentation.eligibleReleasePaths(
                selected: ["owned.txt", "other.txt"],
                locks: [owned, other]
            ),
            ["owned.txt"]
        )
        XCTAssertEqual(
            MacSvnLockActionPresentation.eligibleReleasePaths(
                selected: ["other.txt"],
                locks: [owned, other]
            ),
            []
        )
    }

    func testShelveSeparatesCreationRecordSelectionAndPreviewActions() throws {
        let source = try Self.readFeatureSource(named: "MacSvnShelveView.swift")

        XCTAssertTrue(source.contains("@State private var showCreateShelfSheet"))
        XCTAssertTrue(source.contains("@State private var selectedShelfID"))
        XCTAssertTrue(source.contains("private var shelveToolbar"))
        XCTAssertTrue(source.contains("private var shelveFeedback"))
        XCTAssertTrue(source.contains("private var shelveWorkspace"))
        XCTAssertTrue(source.contains("private var shelfRecordList"))
        XCTAssertTrue(source.contains("private var shelfDetailPane"))
        XCTAssertTrue(source.contains("private var createShelfSheet"))
        XCTAssertTrue(source.contains("private var patchSheet"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"shelve.patch.menu\")"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"shelve.create.button\")"))
        XCTAssertTrue(source.contains(".fixedSize()"))
        XCTAssertTrue(source.contains("private func normalizedWorkingCopyPaths("))
        XCTAssertTrue(source.contains("selected = Set(normalizedWorkingCopyPaths(intent.paths))"))
        XCTAssertTrue(source.contains("normalizedWorkingCopyPaths(pendingPaths)"))
        XCTAssertTrue(source.contains("MacSvnAuxiliaryWorkflowMetrics.masterWidth"))
        XCTAssertTrue(source.contains("DiffPerformanceLimits.truncatedDisplayText("))
        XCTAssertTrue(source.contains("previewRunner.cancel()"))
        XCTAssertTrue(source.contains("previewRunner.enqueue("))
        XCTAssertTrue(source.contains("previewRequestID"))
        XCTAssertTrue(source.contains("MacSvnAuxiliaryLatestRequestPolicy.shouldApply("))
        XCTAssertTrue(source.contains("private var sheetFeedback"))
        XCTAssertTrue(source.contains("MacSvnInlineFeedbackView(feedback: sheetFeedback)"))
        XCTAssertTrue(source.contains("case .error(let message):"))
        XCTAssertTrue(source.contains("ContentUnavailableView(\"没有搁置记录\""))
        XCTAssertTrue(source.contains("确认删除官方 shelf"))
        XCTAssertTrue(source.contains("确认删除本地快照"))
        XCTAssertTrue(source.contains("确认迁移到官方 shelf"))
        XCTAssertTrue(source.contains("pendingMigrationSnapshot"))
        XCTAssertTrue(source.contains("Text(LocalizedStringKey(scope.rawValue))"))
        XCTAssertTrue(source.contains("Text(LocalizedStringKey(kind.rawValue))"))
        XCTAssertGreaterThanOrEqual(
            source.components(separatedBy: ".macSvnDismissibleSheet(").count - 1,
            2,
            "创建搁置和 Patch sheet 都必须有统一关闭入口"
        )
        XCTAssertFalse(source.contains("HSplitView {"))
        XCTAssertFalse(source.contains("VSplitView {"))
    }

    func testLatestAuxiliaryRequestPolicyOnlyAppliesCurrentNonCancelledResult() {
        let current = UUID()
        let stale = UUID()

        XCTAssertTrue(
            MacSvnAuxiliaryLatestRequestPolicy.shouldApply(
                requestID: current,
                currentRequestID: current,
                isCancelled: false
            )
        )
        XCTAssertFalse(
            MacSvnAuxiliaryLatestRequestPolicy.shouldApply(
                requestID: stale,
                currentRequestID: current,
                isCancelled: false
            )
        )
        XCTAssertFalse(
            MacSvnAuxiliaryLatestRequestPolicy.shouldApply(
                requestID: current,
                currentRequestID: current,
                isCancelled: true
            )
        )
    }

    @MainActor
    func testLatestAuxiliaryRequestRunnerDebouncesSupersededWork() async throws {
        let runner = MacSvnAuxiliaryLatestRequestRunner()
        let probe = AuxiliaryRequestProbe()
        var received: [String] = []

        runner.enqueue(
            debounce: .milliseconds(60),
            operation: { await probe.run("stale") },
            receive: { _, result in
                if case .success(let value) = result { received.append(value) }
            }
        )
        runner.enqueue(
            debounce: .milliseconds(60),
            operation: { await probe.run("latest") },
            receive: { _, result in
                if case .success(let value) = result { received.append(value) }
            }
        )

        try await Task.sleep(for: .milliseconds(180))
        let started = await probe.startedValues()

        XCTAssertEqual(started, ["latest"])
        XCTAssertEqual(received, ["latest"])
    }

    func testShelveDynamicLabelsHaveEnglishResources() throws {
        let english = try String(
            contentsOf: Self.repoRoot
                .appendingPathComponent("Sources/MacSvnDesktopApp/Resources/en.lproj/Localizable.strings"),
            encoding: .utf8
        )

        for key in [
            "本地搁置",
            "安全快照",
            "创建官方 Shelf",
            "创建本地搁置",
            "还没有官方 shelf",
            "还没有本地快照",
            "将所选工作副本变更写入 Patch 文件。",
            "从 Patch 文件恢复变更到当前工作副本。",
            "输出文件路径",
            "Patch 文件路径",
        ] {
            XCTAssertTrue(english.contains("\"\(key)\" = "), key)
            XCTAssertFalse(english.contains("\"\(key)\" = \"\(key)\";"), key)
        }
    }

    func testShelveFeedbackPresentationNeverReportsSuccessForFailures() {
        XCTAssertEqual(
            MacSvnShelveFeedbackPresentation.loadOutcome(
                state: .error("offline"),
                officialError: nil
            ),
            .localFailure("offline")
        )
        XCTAssertEqual(
            MacSvnShelveFeedbackPresentation.loadOutcome(
                state: .loaded,
                officialError: "unsupported"
            ),
            .officialFailure("unsupported")
        )
        XCTAssertEqual(
            MacSvnShelveFeedbackPresentation.loadOutcome(
                state: .loaded,
                officialError: nil
            ),
            .refreshed
        )
        XCTAssertEqual(
            MacSvnShelveFeedbackPresentation.operationOutcome(
                state: .error("write failed"),
                expected: .officialShelve
            ),
            .failure("write failed")
        )
        XCTAssertEqual(
            MacSvnShelveFeedbackPresentation.operationOutcome(
                state: .completed(.officialShelve),
                expected: .officialShelve
            ),
            .success
        )
    }

    func testSettingsExposeSearchDirtyStateAndStableSaveFeedback() throws {
        let source = try Self.readFeatureSource(named: "MacSvnSettingsView.swift")

        XCTAssertTrue(source.contains("@State private var settingsSearchText"))
        XCTAssertTrue(source.contains("@State private var baselineDraft"))
        XCTAssertTrue(source.contains("@State private var isSaving"))
        XCTAssertTrue(source.contains("private var filteredCategories"))
        XCTAssertTrue(source.contains("private var currentDraft"))
        XCTAssertTrue(source.contains("private var hasUnsavedChanges"))
        XCTAssertTrue(source.contains("private var settingsSidebar"))
        XCTAssertTrue(source.contains("private var settingsActionBar"))
        XCTAssertTrue(source.contains("SettingsDraftSnapshot("))
        XCTAssertTrue(source.contains("ContentUnavailableView {"))
        XCTAssertTrue(source.contains("Label(\"没有匹配的设置\", systemImage: \"magnifyingglass\")"))
        XCTAssertTrue(source.contains("Button(\"清除搜索\")"))
        XCTAssertTrue(source.contains("guard !isSaving else { return }"))
        XCTAssertTrue(source.contains(".disabled(!hasUnsavedChanges || isSaving)"))
        XCTAssertTrue(source.contains("baselineDraft = currentDraft"))
        XCTAssertTrue(source.contains("navigateToSettingsCategory(.savedData)"))
        XCTAssertTrue(source.contains("navigateToSettingsCategory(.externalPrograms)"))
        XCTAssertTrue(source.contains("MacSvnSettingsErrorPresentation.category(for: error)"))
        let navigationStart = try XCTUnwrap(
            source.range(of: "private func navigateToSettingsCategory(")?.lowerBound
        )
        let navigationEnd = try XCTUnwrap(
            source.range(
                of: "private func clearLogCache()",
                range: navigationStart..<source.endIndex
            )?.lowerBound
        )
        let navigation = source[navigationStart..<navigationEnd]
        XCTAssertTrue(navigation.contains("settingsSearchText = \"\""))
        XCTAssertTrue(navigation.contains("selectedCategory = category"))
    }

    func testAuxiliaryPagesWireKeyboardSearchAndRefreshToRealWorkflows() throws {
        let presentation = try Self.readFeatureSource(named: "MacSvnAuxiliaryWorkflowPresentation.swift")
        let pathList = try Self.sourceSection(startingAt: "struct MacSvnAuxiliaryPathList: View", in: presentation)
        XCTAssertTrue(pathList.contains("var searchFocus: FocusState<Bool>.Binding?"))
        XCTAssertTrue(pathList.contains("searchFocus: FocusState<Bool>.Binding? = nil"))
        XCTAssertTrue(pathList.contains(".focused(searchFocus)"))

        let properties = try Self.readFeatureSource(named: "MacSvnPropertiesView.swift")
        XCTAssertTrue(properties.contains("@FocusState private var isSearchFocused: Bool"))
        XCTAssertTrue(properties.contains("searchFocus: $isSearchFocused"))
        XCTAssertTrue(properties.contains("Button(\"\") { isSearchFocused = true }"))
        XCTAssertTrue(properties.contains(".keyboardShortcut(\"f\", modifiers: .command)"))
        XCTAssertTrue(properties.contains(".accessibilityHidden(true)"))
        let propertiesToolbar = try Self.sourceSection(startingAt: "private var propertiesToolbar", in: properties)
        XCTAssertTrue(propertiesToolbar.contains("requestPropertiesRefresh()"))
        XCTAssertTrue(propertiesToolbar.contains(".keyboardShortcut(\"r\", modifiers: .command)"))
        XCTAssertTrue(propertiesToolbar.contains(".disabled(isPropertyBusy)"))

        let locks = try Self.readFeatureSource(named: "MacSvnLocksView.swift")
        XCTAssertTrue(locks.contains("@FocusState private var isSearchFocused: Bool"))
        XCTAssertTrue(locks.contains("searchFocus: $isSearchFocused"))
        XCTAssertTrue(locks.contains("Button(\"\") { isSearchFocused = true }"))
        XCTAssertTrue(locks.contains(".keyboardShortcut(\"f\", modifiers: .command)"))
        XCTAssertTrue(locks.contains(".accessibilityHidden(true)"))
        let locksToolbar = try Self.sourceSection(startingAt: "private var locksToolbar", in: locks)
        XCTAssertTrue(locksToolbar.contains("requestTargetRefresh()"))
        XCTAssertTrue(locksToolbar.contains(".keyboardShortcut(\"r\", modifiers: .command)"))
        XCTAssertTrue(locksToolbar.contains(".disabled(isBusy)"))

        let shelve = try Self.readFeatureSource(named: "MacSvnShelveView.swift")
        XCTAssertTrue(shelve.contains("@State private var recordSearchText = \"\""))
        XCTAssertTrue(shelve.contains("@FocusState private var isRecordSearchFocused: Bool"))
        XCTAssertTrue(shelve.contains("TextField(\"搜索搁置记录\", text: $recordSearchText)"))
        XCTAssertTrue(shelve.contains(".focused($isRecordSearchFocused)"))
        XCTAssertTrue(shelve.contains("private var filteredOfficialShelves"))
        XCTAssertTrue(shelve.contains("private var filteredLocalSnapshots"))
        XCTAssertTrue(shelve.contains("ForEach(filteredOfficialShelves)"))
        XCTAssertTrue(shelve.contains("ForEach(filteredLocalSnapshots)"))
        XCTAssertTrue(shelve.contains("ContentUnavailableView(\"没有匹配的搁置记录\""))
        XCTAssertTrue(shelve.contains(".onChange(of: recordSearchText) { _, _ in\n            synchronizeRecordSelection(resetPreviewKind: false)"))
        XCTAssertTrue(shelve.contains("Button(\"\") { isRecordSearchFocused = true }"))
        XCTAssertTrue(shelve.contains(".keyboardShortcut(\"f\", modifiers: .command)"))
        XCTAssertTrue(shelve.contains(".accessibilityHidden(true)"))
        let shelveToolbar = try Self.sourceSection(startingAt: "private var shelveToolbar", in: shelve)
        XCTAssertTrue(shelveToolbar.contains("requestShelvesRefresh()"))
        XCTAssertTrue(shelveToolbar.contains(".keyboardShortcut(\"r\", modifiers: .command)"))
        XCTAssertTrue(shelveToolbar.contains(".disabled(isBusy)"))

        let settings = try Self.readFeatureSource(named: "MacSvnSettingsView.swift")
        XCTAssertTrue(settings.contains("@FocusState private var isSettingsSearchFocused: Bool"))
        XCTAssertTrue(settings.contains(".searchFocused($isSettingsSearchFocused)"))
        XCTAssertTrue(settings.contains("Button(\"\") { isSettingsSearchFocused = true }"))
        XCTAssertTrue(settings.contains(".keyboardShortcut(\"f\", modifiers: .command)"))
        XCTAssertTrue(settings.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(settings.contains("Task { await reloadSettings() }"))
        XCTAssertTrue(settings.contains(".keyboardShortcut(\"r\", modifiers: .command)"))
        XCTAssertTrue(settings.contains(".disabled(isLoading || isSaving || hasUnsavedChanges)"))
        let load = try Self.sourceSection(startingAt: "private func load() async", in: settings)
        XCTAssertTrue(load.contains("guard baselineDraft == nil else { return }"))
        let reload = try Self.sourceSection(startingAt: "private func reloadSettings() async", in: settings)
        XCTAssertTrue(reload.contains("guard !isLoading, !isSaving, !hasUnsavedChanges else { return }"))
    }

    func testUserRefreshGuardsCoverFullPageAsyncLifecycles() throws {
        let properties = try Self.readFeatureSource(named: "MacSvnPropertiesView.swift")
        XCTAssertTrue(properties.contains("@State private var isRefreshingProperties = false"))
        let propertiesToolbar = try Self.sourceSection(startingAt: "private var propertiesToolbar", in: properties)
        XCTAssertTrue(propertiesToolbar.contains("requestPropertiesRefresh()"))
        XCTAssertFalse(propertiesToolbar.contains("Task { await loadProperties() }"))
        let propertyBusy = try Self.sourceSection(startingAt: "private var isPropertyBusy", in: properties)
        XCTAssertTrue(propertyBusy.contains("if isRefreshingProperties { return true }"))
        let propertyRequest = try Self.sourceSection(startingAt: "private func requestPropertiesRefresh()", in: properties)
        XCTAssertTrue(propertyRequest.contains("guard !isRefreshingProperties else { return }"))
        XCTAssertTrue(propertyRequest.contains("guard !isPropertyBusy else { return }"))
        XCTAssertTrue(propertyRequest.contains("isRefreshingProperties = true"))
        XCTAssertTrue(propertyRequest.contains("Task { await loadProperties() }"))
        let propertyLoad = try Self.sourceSection(
            startingAt: "private func loadProperties(preservingFeedback: Bool = false) async",
            in: properties
        )
        XCTAssertTrue(propertyLoad.contains("isRefreshingProperties = true"))
        XCTAssertTrue(propertyLoad.contains("defer {"))
        XCTAssertTrue(propertyLoad.contains("generation == loadGeneration"))
        XCTAssertTrue(propertyLoad.contains("isRefreshingProperties = false"))
        XCTAssertTrue(properties.contains(".onChange(of: selected) { _, _ in\n            Task { await loadProperties() }"))

        let locks = try Self.readFeatureSource(named: "MacSvnLocksView.swift")
        XCTAssertTrue(locks.contains("@State private var isRefreshingTargets = false"))
        XCTAssertTrue(locks.contains("@State private var targetRefreshGeneration = 0"))
        let locksToolbar = try Self.sourceSection(startingAt: "private var locksToolbar", in: locks)
        XCTAssertTrue(locksToolbar.contains("requestTargetRefresh()"))
        let lockBusy = try Self.sourceSection(startingAt: "private var isBusy", in: locks)
        XCTAssertTrue(lockBusy.contains("if isRefreshingTargets { return true }"))
        let lockRequest = try Self.sourceSection(startingAt: "private func requestTargetRefresh()", in: locks)
        XCTAssertTrue(lockRequest.contains("guard !isRefreshingTargets else { return }"))
        XCTAssertTrue(lockRequest.contains("guard !isBusy else { return }"))
        XCTAssertTrue(lockRequest.contains("enqueueTargetRefresh()"))
        let targetRefresh = try Self.sourceSection(
            startingAt: "private func enqueueTargetRefresh()",
            in: locks
        )
        XCTAssertTrue(targetRefresh.contains("targetRefreshGeneration += 1"))
        XCTAssertTrue(targetRefresh.contains("isRefreshingTargets = true"))
        XCTAssertFalse(targetRefresh.contains("if !userInitiated"))
        XCTAssertTrue(targetRefresh.contains("defer {"))
        XCTAssertTrue(targetRefresh.contains("refreshGeneration == targetRefreshGeneration"))
        XCTAssertTrue(targetRefresh.contains("isRefreshingTargets = false"))
        XCTAssertTrue(locks.contains(".onChange(of: selected) { _, _ in\n            guard !isApplyingLockIntent else { return }\n            enqueueTargetRefresh()"))
        let pendingIntent = try Self.sourceSection(startingAt: "private func consumePendingLockIntent() async", in: locks)
        XCTAssertTrue(pendingIntent.contains("targetRefreshTask?.cancel()"))
        XCTAssertFalse(pendingIntent.contains("targetRefreshGeneration += 1"))
        XCTAssertFalse(pendingIntent.contains("isRefreshingTargets = false"))

        let shelve = try Self.readFeatureSource(named: "MacSvnShelveView.swift")
        XCTAssertTrue(shelve.contains("@State private var isRefreshingShelves = false"))
        let shelveToolbar = try Self.sourceSection(startingAt: "private var shelveToolbar", in: shelve)
        XCTAssertTrue(shelveToolbar.contains("requestShelvesRefresh()"))
        XCTAssertFalse(shelveToolbar.contains("Task { await refreshShelves() }"))
        let shelveBusy = try Self.sourceSection(startingAt: "private var isBusy", in: shelve)
        XCTAssertTrue(shelveBusy.contains("isRefreshingShelves"))
        let shelveRequest = try Self.sourceSection(startingAt: "private func requestShelvesRefresh()", in: shelve)
        XCTAssertTrue(shelveRequest.contains("guard !isRefreshingShelves else { return }"))
        XCTAssertTrue(shelveRequest.contains("guard !isBusy else { return }"))
        XCTAssertTrue(shelveRequest.contains("isRefreshingShelves = true"))
        XCTAssertTrue(shelveRequest.contains("Task { await refreshShelves() }"))
        let shelveRefresh = try Self.sourceSection(startingAt: "private func refreshShelves() async", in: shelve)
        XCTAssertTrue(shelveRefresh.contains("defer { isRefreshingShelves = false }"))
        XCTAssertTrue(shelveRefresh.contains("await viewModel?.load()"))
    }

    func testShelveSearchSelectionSyncPreservesCurrentPreviewKind() throws {
        let shelve = try Self.readFeatureSource(named: "MacSvnShelveView.swift")
        XCTAssertTrue(shelve.contains(".onChange(of: recordScope) { _, _ in\n            synchronizeRecordSelection()"))
        XCTAssertTrue(shelve.contains(".onChange(of: recordSearchText) { _, _ in\n            synchronizeRecordSelection(resetPreviewKind: false)"))
        let synchronization = try Self.sourceSection(
            startingAt: "private func synchronizeRecordSelection(\n        preferredID: String? = nil,\n        resetPreviewKind: Bool = true\n    )",
            in: shelve
        )
        XCTAssertTrue(synchronization.contains("if resetPreviewKind {\n                previewKind = .diff\n            }"))
        XCTAssertTrue(synchronization.contains("if resetPreviewKind {\n                previewKind = .patch\n            }"))
    }

    func testShelveConfirmationActionsStayDisabledAndPreservePendingWorkWhileBusy() throws {
        let shelve = try Self.readFeatureSource(named: "MacSvnShelveView.swift")
        for marker in [
            "Button(officialDestructiveActionTitle, role: .destructive)",
            "Button(\"删除\", role: .destructive)",
            "Button(\"迁移到官方\", role: .destructive)",
        ] {
            let button = try XCTUnwrap(shelve.range(of: marker))
            let tail = shelve[button.lowerBound...].prefix(300)
            XCTAssertTrue(tail.contains(".disabled(isBusy)"), marker)
        }

        XCTAssertTrue(shelve.contains("Task { await runPendingLocalDelete() }"))
        XCTAssertTrue(shelve.contains("Task { await runPendingMigration() }"))

        let official = try Self.sourceSection(
            startingAt: "private func runPendingOfficialDestructiveAction() async",
            in: shelve
        )
        XCTAssertTrue(official.contains("guard !isBusy else { return }"))
        let officialGuard = try XCTUnwrap(official.range(of: "guard !isBusy else { return }"))
        let officialClear = try XCTUnwrap(official.range(of: "clearPendingOfficialDestructiveAction()"))
        XCTAssertLessThan(officialGuard.lowerBound, officialClear.lowerBound)

        let local = try Self.sourceSection(startingAt: "private func runPendingLocalDelete() async", in: shelve)
        XCTAssertTrue(local.contains("guard !isBusy else { return }"))
        XCTAssertTrue(local.contains("guard let snapshot = pendingLocalSnapshot else { return }"))
        let localGuard = try XCTUnwrap(local.range(of: "guard !isBusy else { return }"))
        let localClear = try XCTUnwrap(local.range(of: "pendingLocalSnapshot = nil"))
        XCTAssertLessThan(localGuard.lowerBound, localClear.lowerBound)

        let migration = try Self.sourceSection(startingAt: "private func runPendingMigration() async", in: shelve)
        XCTAssertTrue(migration.contains("guard !isBusy else { return }"))
        XCTAssertTrue(migration.contains("guard let snapshot = pendingMigrationSnapshot else { return }"))
        let migrationGuard = try XCTUnwrap(migration.range(of: "guard !isBusy else { return }"))
        let migrationClear = try XCTUnwrap(migration.range(of: "pendingMigrationSnapshot = nil"))
        XCTAssertLessThan(migrationGuard.lowerBound, migrationClear.lowerBound)

        let delete = try Self.sourceSection(startingAt: "private func deleteLocalSnapshot(_ snapshot: ShelveSnapshot) async", in: shelve)
        XCTAssertTrue(delete.contains("guard !isBusy else { return }"))
        let migrate = try Self.sourceSection(startingAt: "private func migrate(_ snapshot: ShelveSnapshot) async", in: shelve)
        XCTAssertTrue(migrate.contains("guard !isBusy else { return }"))
    }

    private static func readFeatureSource(named fileName: String) throws -> String {
        try String(
            contentsOf: repoRoot
                .appendingPathComponent("Sources/MacSvnApp/Features", isDirectory: true)
                .appendingPathComponent(fileName),
            encoding: .utf8
        )
    }

    private static func sourceSection(startingAt marker: String, in source: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: marker)?.lowerBound)
        let remaining = source[start...]
        guard let nextDeclaration = remaining.dropFirst(marker.count).range(of: "\n    private ") else {
            return String(remaining)
        }
        return String(source[start..<nextDeclaration.lowerBound])
    }

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let desktopResourcesRoot = repoRoot
        .appendingPathComponent("Sources/MacSvnDesktopApp/Resources", isDirectory: true)
}

private actor AuxiliaryRequestProbe {
    private var started: [String] = []

    func run(_ value: String) -> String {
        started.append(value)
        return value
    }

    func startedValues() -> [String] {
        started
    }
}
