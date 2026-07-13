import XCTest
@testable import MacSvnApp
import MacSvnCore

@MainActor
final class MacSvnAppNavigatorTests: XCTestCase {
    func testChangeListsCommandNavigatesToChangesWithAtomicManagementIntent() {
        let navigator = MacSvnAppNavigator(selectedRoute: .log)

        let result = navigator.perform(command: .changeLists, paths: ["a.swift", "b.swift"])

        XCTAssertEqual(result, .navigated(to: .changes))
        XCTAssertNil(navigator.pendingOpenPath)
        XCTAssertEqual(
            navigator.consumePendingChangelistIntent(),
            PendingChangelistIntent(paths: ["a.swift", "b.swift"])
        )
        XCTAssertNil(navigator.pendingChangelistIntent)
    }

    func testDeepLinkOpenSetsChangesAndPendingPath() {
        let navigator = MacSvnAppNavigator(selectedRoute: .settings)
        navigator.handle(deepLink: .open(path: "/tmp/wc"))

        XCTAssertEqual(navigator.selectedRoute, .changes)
        XCTAssertEqual(navigator.selectedMode, .changes)
        XCTAssertEqual(navigator.pendingOpenPath, "/tmp/wc")
        XCTAssertEqual(navigator.consumePendingOpenPath(), "/tmp/wc")
        XCTAssertNil(navigator.pendingOpenPath)
    }

    func testDeepLinkLogAndDiffSwitchModes() {
        let navigator = MacSvnAppNavigator()
        navigator.handle(deepLink: .log(target: .path("/repo"), revision: nil))
        XCTAssertEqual(navigator.selectedRoute, .log)
        XCTAssertEqual(navigator.selectedMode, .history)
        XCTAssertEqual(navigator.pendingOpenPath, "/repo")

        navigator.handle(deepLink: .diff(target: .repositoryURL("https://svn.example/r"), range: nil))
        XCTAssertEqual(navigator.selectedRoute, .changes)
        XCTAssertEqual(navigator.selectedMode, .changes)
    }

    func testCLICommitUICarriesMessage() {
        let navigator = MacSvnAppNavigator()
        navigator.handle(cli: .commitUI(path: "/wc", initialMessage: "fix: demo"))

        XCTAssertEqual(navigator.selectedRoute, .commit)
        XCTAssertEqual(navigator.selectedMode, .changes)
        XCTAssertEqual(navigator.pendingOpenPath, "/wc")
        XCTAssertEqual(navigator.consumePendingCommitMessage(), "fix: demo")
        XCTAssertNil(navigator.pendingCommitMessage)
    }

    func testCLIStatusOpensChanges() {
        let navigator = MacSvnAppNavigator()
        navigator.handle(cli: .status(path: "/wc"))
        XCTAssertEqual(navigator.selectedRoute, .changes)
        XCTAssertEqual(navigator.pendingOpenPath, "/wc")
    }

    func testNavigateToModeUpdatesRoute() {
        let navigator = MacSvnAppNavigator()
        navigator.selectMode(.conflicts)
        XCTAssertEqual(navigator.selectedRoute, .merge)
        navigator.selectMode(.history)
        XCTAssertEqual(navigator.selectedRoute, .log)
    }

    func testCommandPaletteHandoffCarriesQueryToAIChat() {
        let navigator = MacSvnAppNavigator(selectedRoute: .log)
        navigator.handoffCommandPaletteQueryToAIChat("  帮我总结未提交变更  ")

        XCTAssertEqual(navigator.selectedRoute, .aiAssistant)
        XCTAssertEqual(navigator.pendingAIChatQuery, "帮我总结未提交变更")
        XCTAssertEqual(navigator.consumePendingAIChatQuery(), "帮我总结未提交变更")
        XCTAssertNil(navigator.pendingAIChatQuery)
        XCTAssertTrue(navigator.lastAutomationMessage?.contains("⌘K 转 AI") == true)
    }

    func testCommandPaletteHandoffIgnoresBlankQuery() {
        let navigator = MacSvnAppNavigator(selectedRoute: .changes)
        navigator.handoffCommandPaletteQueryToAIChat("   ")
        XCTAssertEqual(navigator.selectedRoute, .changes)
        XCTAssertNil(navigator.pendingAIChatQuery)
    }

    func testDismissAutomationBanner() {
        let navigator = MacSvnAppNavigator()
        navigator.lastAutomationMessage = "hello"
        navigator.dismissAutomationBanner()
        XCTAssertNil(navigator.lastAutomationMessage)
    }

    func testPerformCommitNavigatesAndCarriesOptions() {
        let navigator = MacSvnAppNavigator(selectedRoute: .settings)
        let result = navigator.perform(
            command: .commit,
            paths: ["/tmp/wc"],
            options: SvnCommandOptions(message: "feat: x")
        )

        XCTAssertEqual(result, .navigated(to: .commit))
        XCTAssertEqual(navigator.lastCommandResult, .navigated(to: .commit))
        XCTAssertEqual(navigator.selectedRoute, .commit)
        XCTAssertEqual(navigator.pendingOpenPath, "/tmp/wc")
        XCTAssertEqual(navigator.pendingCommitMessage, "feat: x")
        XCTAssertTrue(navigator.lastAutomationMessage?.contains("提交") == true)
    }

    func testRevisionGraphCommandNavigatesToImplementedGraphPage() {
        let navigator = MacSvnAppNavigator(selectedRoute: .changes)
        let result = navigator.perform(command: .revisionGraph, paths: ["/tmp/wc"])

        XCTAssertEqual(result, .navigated(to: .revisionGraph))
        XCTAssertEqual(navigator.selectedRoute, .revisionGraph)
        XCTAssertEqual(navigator.pendingOpenPath, "/tmp/wc")
        XCTAssertTrue(navigator.lastAutomationMessage?.contains("修订图") == true)
    }

    func testRevisionGraphNodeHandoffsKeepLogBlameAndCheckoutParametersAtomic() {
        let navigator = MacSvnAppNavigator()
        let logIntent = PendingRevisionGraphLogIntent(
            url: "https://svn.example/repo/branches/feature",
            revision: Revision(9)
        )
        let blameIntent = PendingBlameIntent(
            path: "https://svn.example/repo/branches/feature/App.swift",
            revision: Revision(9)
        )
        navigator.pendingRevisionGraphLog = logIntent
        navigator.pendingBlameIntent = blameIntent

        XCTAssertEqual(navigator.consumePendingRevisionGraphLog(), logIntent)
        XCTAssertNil(navigator.pendingRevisionGraphLog)
        XCTAssertEqual(navigator.consumePendingBlameIntent(), blameIntent)
        XCTAssertNil(navigator.pendingBlameIntent)

        let result = navigator.perform(
            command: .checkout,
            options: SvnCommandOptions(
                revision: Revision(9),
                url: "https://svn.example/repo/branches/feature"
            )
        )
        XCTAssertEqual(result, .navigated(to: .repositoryBrowser))
        XCTAssertEqual(
            navigator.consumePendingTransferIntent(),
            PendingTransferIntent(
                command: .checkout,
                path: nil,
                url: "https://svn.example/repo/branches/feature",
                revision: Revision(9),
                message: nil
            )
        )
    }

    func testFilenameCaseConflictRepairNavigatesToChanges() {
        let navigator = MacSvnAppNavigator(selectedRoute: .settings)
        let result = navigator.perform(command: .repairFilenameCaseConflict, paths: ["/tmp/wc/Foo.txt"])

        XCTAssertEqual(result, .navigated(to: .changes))
        XCTAssertEqual(navigator.selectedRoute, .changes)
        XCTAssertEqual(navigator.pendingOpenPath, "/tmp/wc/Foo.txt")
    }

    func testPerformCheckForModificationsDoesNotSetDiffPath() {
        let navigator = MacSvnAppNavigator()
        _ = navigator.perform(command: .checkForModifications, paths: ["/tmp/wc/file.swift"])
        XCTAssertEqual(navigator.selectedRoute, .changes)
        XCTAssertEqual(navigator.pendingOpenPath, "/tmp/wc/file.swift")
        XCTAssertNil(navigator.pendingDiffPath)
    }

    func testPerformDiffSetsPendingDiffPath() {
        let navigator = MacSvnAppNavigator()
        _ = navigator.perform(command: .diff, paths: ["/tmp/wc/a.swift"])
        XCTAssertEqual(navigator.pendingDiffPath, "/tmp/wc/a.swift")
    }

    func testPerformDiffWithURLCarriesAtomicIntentAndConsumesItOnce() {
        let navigator = MacSvnAppNavigator()
        navigator.pendingDiffPath = "stale.txt"
        navigator.pendingDiffRevision = Revision(99)
        navigator.pendingLogDiff = PendingLogDiffIntent(
            path: "old.txt",
            revision: Revision(98),
            kind: .previous
        )
        let result = navigator.perform(
            command: .diffWithURL,
            paths: ["/tmp/wc", "README.txt"],
            options: SvnCommandOptions(
                revision: Revision(7),
                url: "file:///repo/trunk/README.txt"
            )
        )

        XCTAssertEqual(result, .navigated(to: .diff))
        XCTAssertEqual(navigator.pendingOpenPath, "/tmp/wc")
        XCTAssertNil(navigator.pendingDiffPath)
        XCTAssertNil(navigator.pendingDiffRevision)
        XCTAssertNil(navigator.pendingLogDiff)
        XCTAssertEqual(
            navigator.pendingDiffWithURL,
            PendingDiffWithURLIntent(
                target: "README.txt",
                url: "file:///repo/trunk/README.txt",
                revision: Revision(7)
            )
        )
        XCTAssertEqual(
            navigator.consumePendingDiffWithURL(),
            PendingDiffWithURLIntent(
                target: "README.txt",
                url: "file:///repo/trunk/README.txt",
                revision: Revision(7)
            )
        )
        XCTAssertNil(navigator.pendingDiffWithURL)
    }

    func testPerformDiffWithURLForRelativeTargetDoesNotOpenItAsWorkingCopy() {
        let navigator = MacSvnAppNavigator()

        _ = navigator.perform(command: .diffWithURL, paths: ["README.txt"])

        XCTAssertNil(navigator.pendingOpenPath)
        XCTAssertEqual(
            navigator.pendingDiffWithURL,
            PendingDiffWithURLIntent(target: "README.txt", url: nil, revision: nil)
        )
    }

    func testPerformDiffWithURLDoesNotGuessFromMultipleRelativeTargets() {
        let navigator = MacSvnAppNavigator()

        _ = navigator.perform(command: .diffWithURL, paths: ["A.txt", "B.txt"])

        XCTAssertNil(navigator.pendingOpenPath)
        XCTAssertEqual(
            navigator.pendingDiffWithURL,
            PendingDiffWithURLIntent(target: nil, url: nil, revision: nil)
        )
    }

    func testPerformLockCommandsInjectIntentWithoutOpeningWC() {
        let navigator = MacSvnAppNavigator(selectedRoute: .changes)
        _ = navigator.perform(command: .breakLock, paths: ["locked.txt", "other.txt"])

        XCTAssertEqual(navigator.selectedRoute, .locks)
        XCTAssertNil(navigator.pendingOpenPath)
        XCTAssertEqual(navigator.pendingLockIntent, .breakLock)
        XCTAssertEqual(navigator.consumePendingLockPaths(), ["locked.txt", "other.txt"])
        XCTAssertEqual(navigator.consumePendingLockIntent(), .breakLock)
        XCTAssertNil(navigator.pendingLockIntent)
    }

    func testTortoiseParityCommandsNavigateToBranchAndMergeWorkflows() {
        let navigator = MacSvnAppNavigator()

        XCTAssertEqual(navigator.perform(command: .branchTag), .navigated(to: .branches))
        XCTAssertEqual(navigator.perform(command: .switchBranch), .navigated(to: .branches))
        XCTAssertEqual(navigator.perform(command: .merge), .navigated(to: .merge))
        XCTAssertTrue(navigator.pendingMergeWizard)
        XCTAssertTrue(navigator.consumePendingMergeWizard())
        XCTAssertFalse(navigator.pendingMergeWizard)
    }

    func testPatchCommandsNavigateToShelveAndCarryIntentWithoutOpeningPath() {
        let navigator = MacSvnAppNavigator()
        let options = SvnCommandOptions(extras: ["patchFile": "/tmp/changes.patch"])

        XCTAssertEqual(
            navigator.perform(command: .createPatch, paths: ["README.txt"], options: options),
            .navigated(to: .shelve)
        )
        XCTAssertNil(navigator.pendingOpenPath)
        XCTAssertEqual(
            navigator.consumePendingPatchIntent(),
            PendingPatchIntent(command: .createPatch, paths: ["README.txt"], patchFile: "/tmp/changes.patch")
        )
    }

    func testBlameAndPropertiesCarryRelativePathsWithoutOpeningWorkingCopy() {
        let navigator = MacSvnAppNavigator()

        XCTAssertEqual(navigator.perform(command: .blame, paths: ["README.txt"]), .navigated(to: .blame))
        XCTAssertNil(navigator.pendingOpenPath)
        XCTAssertEqual(
            navigator.consumePendingBlameIntent(),
            PendingBlameIntent(path: "README.txt", revision: nil)
        )

        XCTAssertEqual(navigator.perform(command: .properties, paths: ["src"]), .navigated(to: .properties))
        XCTAssertNil(navigator.pendingOpenPath)
        XCTAssertEqual(navigator.consumePendingPropertyPath(), "src")
    }

    func testMergeConflictNavigationPreservesFirstConflictPath() {
        let navigator = MacSvnAppNavigator(selectedRoute: .changes)

        navigator.openMergeConflicts(paths: ["src/conflict.swift"])

        XCTAssertEqual(navigator.selectedRoute, .merge)
        XCTAssertEqual(navigator.pendingConflictPath, "src/conflict.swift")
        XCTAssertFalse(navigator.pendingMergeWizard)
    }


    func testPerformCoversEveryCatalogIDWithoutCrash() {
        let navigator = MacSvnAppNavigator()
        for id in SvnCommandID.allCases {
            let result = navigator.perform(command: id)
            switch result {
            case .navigated:
                XCTAssertNotNil(MacSvnAppNavigator.route(for: id))
            case .unimplemented(let command):
                XCTAssertEqual(command, id)
                XCTAssertNil(MacSvnAppNavigator.route(for: id))
            }
        }
    }
}
