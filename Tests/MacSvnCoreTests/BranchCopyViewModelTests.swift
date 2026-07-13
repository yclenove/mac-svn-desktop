import XCTest
@testable import MacSvnCore

final class BranchCopyViewModelTests: XCTestCase {
    @MainActor
    func testCreateFromHeadStripsExistingPegRevision() async {
        let provider = FakeBranchCopyProvider(result: .success(Revision(20)))
        let viewModel = BranchCopyViewModel(copyProvider: provider)

        await viewModel.create(
            kind: .branch,
            source: .head(repositoryURL: "file:///repo/trunk@19"),
            repositoryRoot: "file:///repo",
            name: "feature-head",
            layout: BranchLayout(),
            message: "create from HEAD"
        )

        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls.single?.source, "file:///repo/trunk")
    }

    @MainActor
    func testCreateFromRevisionPreservesUserAtHostAndPinsPegRevision() async {
        let provider = FakeBranchCopyProvider(result: .success(Revision(21)))
        let viewModel = BranchCopyViewModel(copyProvider: provider)

        await viewModel.create(
            kind: .tag,
            source: .revision(
                repositoryURL: "svn+ssh://user@host/repo/trunk@18",
                revision: Revision(12)
            ),
            repositoryRoot: "svn+ssh://user@host/repo",
            name: "v1.2",
            layout: BranchLayout(),
            message: "tag r12"
        )

        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls.single?.source, "svn+ssh://user@host/repo/trunk@12")
    }

    @MainActor
    func testCreateFromWorkingCopyUsesLocalPath() async {
        let provider = FakeBranchCopyProvider(result: .success(Revision(22)))
        let viewModel = BranchCopyViewModel(copyProvider: provider)

        await viewModel.create(
            kind: .branch,
            source: .workingCopy(URL(fileURLWithPath: "/tmp/wc")),
            repositoryRoot: "file:///repo",
            name: "feature-wc",
            layout: BranchLayout(),
            message: "copy local changes"
        )

        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls.single?.source, "/tmp/wc")
    }

    @MainActor
    func testCreateBranchBuildsDestinationFromLayoutAndStoresRevision() async {
        let provider = FakeBranchCopyProvider(result: .success(Revision(12)))
        let viewModel = BranchCopyViewModel(copyProvider: provider)
        let auth = Credential(username: "u", password: "p")

        await viewModel.create(
            kind: .branch,
            source: "file:///repo/trunk",
            repositoryRoot: "file:///repo",
            name: "feature-one",
            layout: BranchLayout(),
            message: "创建分支：feature-one",
            auth: auth
        )
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .completed(Revision(12)))
        XCTAssertEqual(viewModel.createdRevision, Revision(12))
        XCTAssertEqual(calls, [
            BranchCopyCall(
                source: "file:///repo/trunk",
                destination: "file:///repo/branches/feature-one",
                message: "创建分支：feature-one",
                auth: auth
            )
        ])
    }

    @MainActor
    func testCreateTagUsesTagsLayout() async {
        let provider = FakeBranchCopyProvider(result: .success(Revision(13)))
        let viewModel = BranchCopyViewModel(copyProvider: provider)
        let layout = BranchLayout(trunk: "main", branches: "dev", tags: "releases")

        await viewModel.create(
            kind: .tag,
            source: "file:///repo/main",
            repositoryRoot: "file:///repo",
            name: "v1.0",
            layout: layout,
            message: "tag v1.0",
            auth: nil
        )
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .completed(Revision(13)))
        XCTAssertEqual(calls, [
            BranchCopyCall(
                source: "file:///repo/main",
                destination: "file:///repo/releases/v1.0",
                message: "tag v1.0",
                auth: nil
            )
        ])
    }

    @MainActor
    func testCreateRejectsEmptyNameBeforeProviderCall() async {
        let provider = FakeBranchCopyProvider(result: .success(Revision(1)))
        let viewModel = BranchCopyViewModel(copyProvider: provider)

        await viewModel.create(
            kind: .branch,
            source: "file:///repo/trunk",
            repositoryRoot: "file:///repo",
            name: "  ",
            layout: BranchLayout(),
            message: "create",
            auth: nil
        )
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .error("emptyBranchName"))
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor
    func testCreateFailureStoresErrorAndClearsRevision() async {
        let provider = FakeBranchCopyProvider(result: .failure(SvnError.network(detail: "offline")))
        let viewModel = BranchCopyViewModel(copyProvider: provider)

        await viewModel.create(
            kind: .branch,
            source: "file:///repo/trunk",
            repositoryRoot: "file:///repo",
            name: "dev",
            layout: BranchLayout(),
            message: "create",
            auth: nil
        )

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertNil(viewModel.createdRevision)
    }
}

private struct BranchCopyCall: Equatable, Sendable {
    let source: String
    let destination: String
    let message: String
    let auth: Credential?
}

private actor FakeBranchCopyProvider: BranchCopyProviding {
    private let result: Result<Revision, Error>
    private var calls: [BranchCopyCall] = []

    init(result: Result<Revision, Error>) {
        self.result = result
    }

    func recordedCalls() -> [BranchCopyCall] {
        calls
    }

    func copy(source: String, destination: String, message: String, auth: Credential?) async throws -> Revision {
        calls.append(BranchCopyCall(source: source, destination: destination, message: message, auth: auth))
        return try result.get()
    }
}

private extension Array {
    var single: Element? {
        count == 1 ? first : nil
    }
}
