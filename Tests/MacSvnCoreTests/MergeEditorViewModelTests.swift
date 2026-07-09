import XCTest
@testable import MacSvnCore

final class MergeEditorViewModelTests: XCTestCase {
    @MainActor
    func testLoadTextConflictBuildsMergeBlocksAndSelectsFirstConflict() async {
        let conflict = textConflict()
        let provider = FakeMergeEditorProvider(loadResult: .success((
            base: "a\nbase\nz\n",
            mine: "a\nmine\nz\n",
            theirs: "a\ntheirs\nz\n"
        )))
        let viewModel = MergeEditorViewModel(provider: provider)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        await viewModel.load(conflict: conflict, wc: wc)

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.conflict, conflict)
        XCTAssertEqual(viewModel.workingCopy, wc)
        XCTAssertEqual(viewModel.conflictBlockIndices, [1])
        XCTAssertEqual(viewModel.currentConflictIndex, 0)
        XCTAssertEqual(viewModel.unresolvedConflictCount, 1)
        XCTAssertFalse(viewModel.canSaveResolved)
        let loadCalls = await provider.recordedLoadCalls()
        XCTAssertEqual(loadCalls, [conflict])
    }

    @MainActor
    func testNavigationMovesAcrossConflictBlocks() async {
        let provider = FakeMergeEditorProvider(loadResult: .success((
            base: "one\nsame\ntwo\n",
            mine: "mine-one\nsame\nmine-two\n",
            theirs: "theirs-one\nsame\ntheirs-two\n"
        )))
        let viewModel = MergeEditorViewModel(provider: provider)

        await viewModel.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
        viewModel.nextConflict()
        XCTAssertEqual(viewModel.currentConflictIndex, 1)
        viewModel.nextConflict()
        XCTAssertEqual(viewModel.currentConflictIndex, 1)
        viewModel.previousConflict()
        XCTAssertEqual(viewModel.currentConflictIndex, 0)
    }

    @MainActor
    func testResolveCurrentConflictUpdatesBlocksAndSaveReadiness() async {
        let provider = FakeMergeEditorProvider(loadResult: .success((
            base: "a\nbase\nz\n",
            mine: "a\nmine\nz\n",
            theirs: "a\ntheirs\nz\n"
        )))
        let viewModel = MergeEditorViewModel(provider: provider)

        await viewModel.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
        viewModel.resolveCurrent(.takeMine)

        XCTAssertEqual(viewModel.unresolvedConflictCount, 0)
        XCTAssertTrue(viewModel.canSaveResolved)
        XCTAssertEqual(viewModel.mergedText(), "a\nmine\nz\n")
    }

    @MainActor
    func testManualResolutionAndTakeBothAreAppliedToMergedText() async {
        let provider = FakeMergeEditorProvider(loadResult: .success((
            base: "a\nbase\nz\n",
            mine: "a\nmine\nz\n",
            theirs: "a\ntheirs\nz\n"
        )))
        let viewModel = MergeEditorViewModel(provider: provider)

        await viewModel.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
        viewModel.resolveCurrent(.takeBoth(mineFirst: false))
        XCTAssertEqual(viewModel.mergedText(), "a\ntheirs\nmine\nz\n")

        viewModel.resolveConflict(atConflictIndex: 0, resolution: .manual(lines: ["manual"]))
        XCTAssertEqual(viewModel.mergedText(), "a\nmanual\nz\n")
    }

    @MainActor
    func testSaveBlocksWhenConflictsRemain() async {
        let provider = FakeMergeEditorProvider(loadResult: .success((
            base: "base\n",
            mine: "mine\n",
            theirs: "theirs\n"
        )))
        let viewModel = MergeEditorViewModel(provider: provider)

        await viewModel.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
        await viewModel.saveResolved()

        XCTAssertEqual(viewModel.state, .error("unresolvedConflicts"))
        let saveCalls = await provider.recordedSaveCalls()
        XCTAssertTrue(saveCalls.isEmpty)
    }

    @MainActor
    func testSaveResolvedWritesMergedTextThroughProvider() async {
        let conflict = textConflict()
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakeMergeEditorProvider(loadResult: .success((
            base: "base\n",
            mine: "mine\n",
            theirs: "theirs\n"
        )))
        let viewModel = MergeEditorViewModel(provider: provider)

        await viewModel.load(conflict: conflict, wc: wc)
        viewModel.resolveCurrent(.takeTheirs)
        await viewModel.saveResolved()

        XCTAssertEqual(viewModel.state, .saved)
        let saveCalls = await provider.recordedSaveCalls()
        XCTAssertEqual(saveCalls, [
            MergeEditorSaveCall(conflict: conflict, wc: wc, mergedText: "theirs\n")
        ])
    }

    @MainActor
    func testSaveFailureStoresError() async {
        let provider = FakeMergeEditorProvider(
            loadResult: .success((
                base: "base\n",
                mine: "mine\n",
                theirs: "theirs\n"
            )),
            saveError: SvnError.network(detail: "offline")
        )
        let viewModel = MergeEditorViewModel(provider: provider)

        await viewModel.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
        viewModel.resolveCurrent(.takeMine)
        await viewModel.saveResolved()

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
    }

    @MainActor
    func testResolveWholeFileMineForwardsMineFullAndMarksSaved() async {
        let conflict = textConflict()
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakeMergeEditorProvider(loadResult: .success((
            base: "base\n",
            mine: "mine\n",
            theirs: "theirs\n"
        )))
        let viewModel = MergeEditorViewModel(provider: provider)

        await viewModel.load(conflict: conflict, wc: wc)
        viewModel.resolveCurrent(.takeMine)
        await viewModel.resolveWholeFileMine()

        XCTAssertEqual(viewModel.state, .saved)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertFalse(viewModel.shouldWarnBeforeClose)
        let calls = await provider.recordedWholeFileResolveCalls()
        XCTAssertEqual(calls, [
            MergeEditorWholeFileResolveCall(conflict: conflict, wc: wc, accept: .mineFull)
        ])
    }

    @MainActor
    func testResolveWholeFileTheirsForwardsTheirsFullAndMarksSaved() async {
        let conflict = textConflict()
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakeMergeEditorProvider(loadResult: .success((
            base: "base\n",
            mine: "mine\n",
            theirs: "theirs\n"
        )))
        let viewModel = MergeEditorViewModel(provider: provider)

        await viewModel.load(conflict: conflict, wc: wc)
        await viewModel.resolveWholeFileTheirs()

        XCTAssertEqual(viewModel.state, .saved)
        let calls = await provider.recordedWholeFileResolveCalls()
        XCTAssertEqual(calls, [
            MergeEditorWholeFileResolveCall(conflict: conflict, wc: wc, accept: .theirsFull)
        ])
    }

    @MainActor
    func testResolveWholeFileFailureStoresErrorAndKeepsDirtyState() async {
        let provider = FakeMergeEditorProvider(
            loadResult: .success((
                base: "base\n",
                mine: "mine\n",
                theirs: "theirs\n"
            )),
            wholeFileResolveError: SvnError.network(detail: "offline")
        )
        let viewModel = MergeEditorViewModel(provider: provider)

        await viewModel.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
        viewModel.resolveCurrent(.takeMine)
        XCTAssertTrue(viewModel.hasUnsavedChanges)

        await viewModel.resolveWholeFileMine()

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertTrue(viewModel.shouldWarnBeforeClose)
    }

    @MainActor
    func testDirtyStateTracksLoadResolveSaveAndDiscard() async {
        let conflict = textConflict()
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakeMergeEditorProvider(loadResult: .success((
            base: "a\nbase\nz\n",
            mine: "a\nmine\nz\n",
            theirs: "a\ntheirs\nz\n"
        )))
        let viewModel = MergeEditorViewModel(provider: provider)

        await viewModel.load(conflict: conflict, wc: wc)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertFalse(viewModel.shouldWarnBeforeClose)

        viewModel.resolveCurrent(.manual(lines: ["manual"]))
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertTrue(viewModel.shouldWarnBeforeClose)

        viewModel.discardEdits()
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertFalse(viewModel.shouldWarnBeforeClose)
        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.unresolvedConflictCount, 1)

        viewModel.resolveCurrent(.takeTheirs)
        await viewModel.saveResolved()

        XCTAssertEqual(viewModel.state, .saved)
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertFalse(viewModel.shouldWarnBeforeClose)
    }

    @MainActor
    func testSaveFailureKeepsUnsavedChanges() async {
        let provider = FakeMergeEditorProvider(
            loadResult: .success((
                base: "base\n",
                mine: "mine\n",
                theirs: "theirs\n"
            )),
            saveError: SvnError.network(detail: "offline")
        )
        let viewModel = MergeEditorViewModel(provider: provider)

        await viewModel.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
        viewModel.resolveCurrent(.takeMine)
        await viewModel.saveResolved()

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertTrue(viewModel.shouldWarnBeforeClose)
    }

    @MainActor
    func testAIConflictSuggestionPrefillsCurrentConflictAsManualResolutionWithoutSaving() async {
        let provider = FakeMergeEditorProvider(loadResult: .success((
            base: "a\nbase\nz\n",
            mine: "a\nmine\nz\n",
            theirs: "a\ntheirs\nz\n"
        )))
        let suggestion = AIConflictAssistSuggestion(
            mergedLines: ["ai merged"],
            rationale: "保留双方语义。",
            confidence: .medium,
            providerID: UUID(),
            redactionMatches: [],
            promptCount: 1
        )
        let assistant = FakeAIConflictAssistant(result: .success(suggestion))
        let viewModel = MergeEditorViewModel(provider: provider, aiConflictAssistant: assistant)
        let conflict = textConflict(path: "Sources/Login.swift")
        let wc = URL(fileURLWithPath: "/tmp/wc")

        await viewModel.load(conflict: conflict, wc: wc)
        await viewModel.requestAIResolutionForCurrentConflict()

        XCTAssertEqual(viewModel.aiConflictAssistState, .suggested(suggestion))
        XCTAssertEqual(viewModel.aiConflictSuggestion, suggestion)
        XCTAssertEqual(viewModel.unresolvedConflictCount, 0)
        XCTAssertEqual(viewModel.mergedText(), "a\nai merged\nz\n")
        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertTrue(viewModel.canSaveResolved)
        let calls = await assistant.recordedCalls()
        XCTAssertEqual(calls.map(\.context.path), ["Sources/Login.swift"])
        XCTAssertEqual(calls[0].context.baseLines, ["base"])
        XCTAssertEqual(calls[0].context.mineLines, ["mine"])
        XCTAssertEqual(calls[0].context.theirsLines, ["theirs"])
        let saveCalls = await provider.recordedSaveCalls()
        let wholeFileCalls = await provider.recordedWholeFileResolveCalls()
        XCTAssertTrue(saveCalls.isEmpty)
        XCTAssertTrue(wholeFileCalls.isEmpty)
    }

    @MainActor
    func testAIConflictSuggestionUnavailableMissingConflictAndProviderErrors() async {
        let provider = FakeMergeEditorProvider(loadResult: .success((
            base: "base\n",
            mine: "mine\n",
            theirs: "theirs\n"
        )))
        let noAssistant = MergeEditorViewModel(provider: provider)

        await noAssistant.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
        await noAssistant.requestAIResolutionForCurrentConflict()
        XCTAssertEqual(noAssistant.aiConflictAssistState, .error("aiConflictAssistantUnavailable"))

        let assistant = FakeAIConflictAssistant(result: .failure(AIConflictAssistError.emptyConflict))
        let noConflictLoaded = MergeEditorViewModel(provider: provider, aiConflictAssistant: assistant)
        await noConflictLoaded.requestAIResolutionForCurrentConflict()
        XCTAssertEqual(noConflictLoaded.aiConflictAssistState, .error("missingConflict"))

        let loaded = MergeEditorViewModel(provider: provider, aiConflictAssistant: assistant)
        await loaded.load(conflict: textConflict(), wc: URL(fileURLWithPath: "/tmp/wc"))
        await loaded.requestAIResolutionForCurrentConflict()
        XCTAssertEqual(
            loaded.aiConflictAssistState,
            .error(String(describing: AIConflictAssistError.emptyConflict))
        )
    }
}

private func textConflict(path: String = "README.txt") -> ConflictInfo {
    ConflictInfo(
        path: path,
        kind: .text,
        baseFile: nil,
        mineFile: nil,
        theirsFile: nil,
        treeConflict: nil
    )
}

struct MergeEditorSaveCall: Equatable {
    let conflict: ConflictInfo
    let wc: URL
    let mergedText: String
}

struct MergeEditorWholeFileResolveCall: Equatable {
    let conflict: ConflictInfo
    let wc: URL
    let accept: ResolveAccept
}

actor FakeMergeEditorProvider: TextConflictLoading, ConflictResolutionSaving, WholeFileConflictResolving {
    let loadResult: Result<(base: String, mine: String, theirs: String), Error>
    let saveError: Error?
    let wholeFileResolveError: Error?
    private var loadCalls: [ConflictInfo] = []
    private var saveCalls: [MergeEditorSaveCall] = []
    private var wholeFileResolveCalls: [MergeEditorWholeFileResolveCall] = []

    init(
        loadResult: Result<(base: String, mine: String, theirs: String), Error>,
        saveError: Error? = nil,
        wholeFileResolveError: Error? = nil
    ) {
        self.loadResult = loadResult
        self.saveError = saveError
        self.wholeFileResolveError = wholeFileResolveError
    }

    func loadTextConflict(_ conflict: ConflictInfo) async throws -> (base: String, mine: String, theirs: String) {
        loadCalls.append(conflict)
        return try loadResult.get()
    }

    func saveResolution(_ conflict: ConflictInfo, wc: URL, mergedText: String) async throws {
        if let saveError {
            throw saveError
        }
        saveCalls.append(MergeEditorSaveCall(conflict: conflict, wc: wc, mergedText: mergedText))
    }

    func resolveWholeFile(_ conflict: ConflictInfo, wc: URL, accept: ResolveAccept) async throws {
        if let wholeFileResolveError {
            throw wholeFileResolveError
        }
        wholeFileResolveCalls.append(MergeEditorWholeFileResolveCall(conflict: conflict, wc: wc, accept: accept))
    }

    func recordedLoadCalls() -> [ConflictInfo] {
        loadCalls
    }

    func recordedSaveCalls() -> [MergeEditorSaveCall] {
        saveCalls
    }

    func recordedWholeFileResolveCalls() -> [MergeEditorWholeFileResolveCall] {
        wholeFileResolveCalls
    }
}

private struct AIConflictAssistCall: Equatable, Sendable {
    let context: AIConflictAssistContext
    let privacySettings: AIPrivacySettings
}

private actor FakeAIConflictAssistant: AIConflictAssisting {
    private let result: Result<AIConflictAssistSuggestion, Error>
    private var calls: [AIConflictAssistCall] = []

    init(result: Result<AIConflictAssistSuggestion, Error>) {
        self.result = result
    }

    func recordedCalls() -> [AIConflictAssistCall] {
        calls
    }

    func suggestResolution(
        context: AIConflictAssistContext,
        privacySettings: AIPrivacySettings
    ) async throws -> AIConflictAssistSuggestion {
        calls.append(AIConflictAssistCall(context: context, privacySettings: privacySettings))
        return try result.get()
    }
}
