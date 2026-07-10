import Foundation
import XCTest
@testable import MacSvnCore

final class AIReleaseNotesViewModelTests: XCTestCase {
    @MainActor
    func testLoadEntriesMarksReadyAndGenerateStoresDraft() async {
        let entries = [sampleEntry(revision: 2), sampleEntry(revision: 1)]
        let draft = AIReleaseNotesDraft(
            title: "v1",
            markdown: "# v1",
            sections: [AIReleaseNotesSection(title: "新功能", items: ["A"])],
            providerID: UUID(),
            entryCount: 2,
            redactionMatches: [],
            promptCount: 1
        )
        let viewModel = AIReleaseNotesViewModel(
            logProvider: FakeReleaseNotesLogProvider(result: .success([])),
            generator: FakeReleaseNotesGenerator(result: .success(draft))
        )

        viewModel.loadEntries(entries)
        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(viewModel.entries.count, 2)

        await viewModel.generate(privacySettings: AIPrivacySettings())

        XCTAssertEqual(viewModel.state, .completed(draft))
        XCTAssertEqual(viewModel.draft, draft)
    }

    @MainActor
    func testLoadRecentLogsStoresEntries() async {
        let entries = [sampleEntry(revision: 9)]
        let provider = FakeReleaseNotesLogProvider(result: .success(entries))
        let viewModel = AIReleaseNotesViewModel(
            logProvider: provider,
            generator: FakeReleaseNotesGenerator(result: .failure(AIReleaseNotesError.emptyLogSelection))
        )
        let wc = URL(fileURLWithPath: "/tmp/wc")

        await viewModel.loadRecentLogs(wc: wc, batch: 20)
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .ready)
        XCTAssertEqual(viewModel.entries, entries)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].wc, wc)
        XCTAssertEqual(calls[0].batch, 20)
    }

    @MainActor
    func testGenerateWithoutEntriesStoresEmptySelectionError() async {
        let viewModel = AIReleaseNotesViewModel(
            logProvider: FakeReleaseNotesLogProvider(result: .success([])),
            generator: FakeReleaseNotesGenerator(result: .success(
                AIReleaseNotesDraft(
                    title: "x",
                    markdown: "# x",
                    sections: [],
                    providerID: UUID(),
                    entryCount: 0,
                    redactionMatches: [],
                    promptCount: 0
                )
            ))
        )

        await viewModel.generate(privacySettings: AIPrivacySettings())

        XCTAssertEqual(
            viewModel.state,
            .error(String(describing: AIReleaseNotesError.emptyLogSelection))
        )
    }
}

private func sampleEntry(revision: Int) -> LogEntry {
    LogEntry(
        revision: Revision(revision),
        author: "dev",
        date: nil,
        message: "msg \(revision)",
        changedPaths: []
    )
}

private struct ReleaseNotesLogCall: Equatable, Sendable {
    let wc: URL
    let batch: Int
}

private actor FakeReleaseNotesLogProvider: LogProviding {
    private let result: Result<[LogEntry], Error>
    private var calls: [ReleaseNotesLogCall] = []

    init(result: Result<[LogEntry], Error>) {
        self.result = result
    }

    func recordedCalls() -> [ReleaseNotesLogCall] { calls }

    func log(
        wc: URL,
        target: String,
        from: Revision,
        batch: Int,
        verbose: Bool,
        stopOnCopy: Bool
    ) async throws -> [LogEntry] {
        calls.append(ReleaseNotesLogCall(wc: wc, batch: batch))
        return try result.get()
    }
}

private struct FakeReleaseNotesGenerator: AIReleaseNotesGenerating {
    let result: Result<AIReleaseNotesDraft, Error>

    func generate(
        entries: [LogEntry],
        title: String,
        template: AIReleaseNotesTemplate,
        privacySettings: AIPrivacySettings
    ) async throws -> AIReleaseNotesDraft {
        try result.get()
    }
}
