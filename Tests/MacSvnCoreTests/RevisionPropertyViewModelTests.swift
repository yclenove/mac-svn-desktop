import Foundation
import XCTest
@testable import MacSvnCore

final class RevisionPropertyViewModelTests: XCTestCase {
    @MainActor
    func testLoadAndSaveAuthorAndMessageRefreshAllRevisionProperties() async {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakeRevisionPropertyProvider(results: [
            .success([
                SvnProperty(target: "r7", name: "svn:author", value: "old-author"),
                SvnProperty(target: "r7", name: "svn:log", value: "old message"),
                SvnProperty(target: "r7", name: "custom:reviewed", value: "yes")
            ]),
            .success([
                SvnProperty(target: "r7", name: "svn:author", value: "new-author"),
                SvnProperty(target: "r7", name: "svn:log", value: "new message"),
                SvnProperty(target: "r7", name: "custom:reviewed", value: "yes")
            ])
        ])
        let viewModel = RevisionPropertyViewModel(
            workingCopy: wc,
            target: "file:///repo",
            revision: Revision(7),
            provider: provider
        )

        await viewModel.load()
        XCTAssertEqual(viewModel.author, "old-author")
        XCTAssertEqual(viewModel.message, "old message")
        XCTAssertEqual(viewModel.properties.count, 3)

        await viewModel.save(author: " new-author ", message: "new message")

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.author, "new-author")
        XCTAssertEqual(viewModel.message, "new message")
        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [
            .read(revision: Revision(7)),
            .write(revision: Revision(7), name: "svn:author", value: "new-author"),
            .write(revision: Revision(7), name: "svn:log", value: "new message"),
            .read(revision: Revision(7))
        ])
    }

    @MainActor
    func testSaveRejectsBlankAuthorBeforeWriting() async {
        let provider = FakeRevisionPropertyProvider(results: [])
        let viewModel = RevisionPropertyViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "file:///repo",
            revision: Revision(7),
            provider: provider
        )

        await viewModel.save(author: "   ", message: "message")

        XCTAssertEqual(viewModel.state, .error("emptyRevisionAuthor"))
        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [])
    }

    @MainActor
    func testSaveWritesOnlyChangedRevisionProperties() async {
        let provider = FakeRevisionPropertyProvider(results: [
            .success([
                SvnProperty(target: "r7", name: "svn:author", value: "same-author"),
                SvnProperty(target: "r7", name: "svn:log", value: "old message")
            ]),
            .success([
                SvnProperty(target: "r7", name: "svn:author", value: "same-author"),
                SvnProperty(target: "r7", name: "svn:log", value: "new message")
            ])
        ])
        let viewModel = RevisionPropertyViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            target: "file:///repo",
            revision: Revision(7),
            provider: provider
        )

        await viewModel.load()
        await viewModel.save(author: "same-author", message: "new message")

        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [
            .read(revision: Revision(7)),
            .write(revision: Revision(7), name: "svn:log", value: "new message"),
            .read(revision: Revision(7))
        ])
    }
}

private enum RevisionPropertyCall: Equatable {
    case read(revision: Revision)
    case write(revision: Revision, name: String, value: String)
}

private actor FakeRevisionPropertyProvider: RevisionPropertyProviding {
    private var results: [Result<[SvnProperty], Error>]
    private var calls: [RevisionPropertyCall] = []

    init(results: [Result<[SvnProperty], Error>]) {
        self.results = results
    }

    func recordedCalls() -> [RevisionPropertyCall] { calls }

    func revisionProperties(
        wc: URL,
        target: String,
        revision: Revision
    ) async throws -> [SvnProperty] {
        calls.append(.read(revision: revision))
        return try results.removeFirst().get()
    }

    func setRevisionProperty(
        wc: URL,
        target: String,
        revision: Revision,
        name: String,
        value: String
    ) async throws {
        calls.append(.write(revision: revision, name: name, value: value))
    }
}
