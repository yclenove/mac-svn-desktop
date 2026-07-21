import Foundation
import XCTest
@testable import MacSvnCore

final class CheckoutViewModelTests: XCTestCase {
    @MainActor
    func testCheckoutURLRunsProviderAndImportsWorkingCopy() async {
        let record = workingCopyRecord(path: "/tmp/wc", repoURL: "file:///repo/trunk")
        let checkoutProvider = FakeCheckoutProvider()
        let importer = FakeWorkspaceImporter(result: .success(record))
        let infoProvider = FakeInfoProvider()
        let viewModel = CheckoutViewModel(
            checkoutProvider: checkoutProvider,
            workspaceImporter: importer,
            infoProvider: infoProvider
        )
        let destination = URL(fileURLWithPath: "/tmp/wc")
        let auth = Credential(username: "u", password: "p")

        await viewModel.checkout(
            url: "file:///repo/trunk",
            to: destination,
            depth: .files,
            auth: auth,
            username: "u",
            name: "Main"
        )

        let checkoutCalls = await checkoutProvider.recordedCalls()
        let importCalls = await importer.recordedCalls()

        XCTAssertEqual(viewModel.state, .completed(record))
        XCTAssertEqual(viewModel.importedWorkingCopy, record)
        XCTAssertEqual(checkoutCalls, [
            CheckoutCall(url: "file:///repo/trunk", destination: destination, depth: .files, auth: auth)
        ])
        XCTAssertEqual(importCalls, [
            WorkspaceImportCall(localPath: destination, username: "u", name: "Main")
        ])
    }

    @MainActor
    func testCheckoutFailureDoesNotImportWorkingCopy() async {
        let checkoutProvider = FakeCheckoutProvider(error: SvnError.network(detail: "offline"))
        let importer = FakeWorkspaceImporter(result: .success(workingCopyRecord(path: "/tmp/wc", repoURL: "file:///repo/trunk")))
        let viewModel = CheckoutViewModel(
            checkoutProvider: checkoutProvider,
            workspaceImporter: importer,
            infoProvider: FakeInfoProvider()
        )

        await viewModel.checkout(url: "file:///repo/trunk", to: URL(fileURLWithPath: "/tmp/wc"), depth: .empty)

        let importCalls = await importer.recordedCalls()

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertTrue(importCalls.isEmpty)
    }

    @MainActor
    func testImportFailureStoresErrorAfterCheckout() async {
        let checkoutProvider = FakeCheckoutProvider()
        let importer = FakeWorkspaceImporter(result: .failure(WorkspaceStoreError.invalidWorkingCopy(path: "/tmp/wc")))
        let viewModel = CheckoutViewModel(
            checkoutProvider: checkoutProvider,
            workspaceImporter: importer,
            infoProvider: FakeInfoProvider()
        )

        await viewModel.checkout(url: "file:///repo/trunk", to: URL(fileURLWithPath: "/tmp/wc"), depth: .empty)

        XCTAssertEqual(
            viewModel.state,
            .error(String(describing: WorkspaceStoreError.invalidWorkingCopy(path: "/tmp/wc")))
        )
    }

    @MainActor
    func testCheckoutRemoteDirectoryEntryBuildsUrlAndUsesDepth() async {
        let record = workingCopyRecord(path: "/tmp/src", repoURL: "file:///repo/trunk/src")
        let checkoutProvider = FakeCheckoutProvider()
        let importer = FakeWorkspaceImporter(result: .success(record))
        let viewModel = CheckoutViewModel(
            checkoutProvider: checkoutProvider,
            workspaceImporter: importer,
            infoProvider: FakeInfoProvider()
        )
        let entry = RemoteEntry(name: "src", path: "src", kind: .directory, size: nil, revision: nil, author: nil, date: nil)

        await viewModel.checkout(entry: entry, baseURL: "file:///repo/trunk", to: URL(fileURLWithPath: "/tmp/src"), depth: .immediates)

        let checkoutCalls = await checkoutProvider.recordedCalls()

        XCTAssertEqual(checkoutCalls, [
            CheckoutCall(url: "file:///repo/trunk/src", destination: URL(fileURLWithPath: "/tmp/src"), depth: .immediates, auth: nil)
        ])
        XCTAssertEqual(viewModel.state, .completed(record))
    }

    @MainActor
    func testCheckoutRemoteFileEntryIsRejectedBeforeProviderCall() async {
        let checkoutProvider = FakeCheckoutProvider()
        let importer = FakeWorkspaceImporter(result: .success(workingCopyRecord(path: "/tmp/readme", repoURL: "file:///repo/trunk/README.txt")))
        let viewModel = CheckoutViewModel(
            checkoutProvider: checkoutProvider,
            workspaceImporter: importer,
            infoProvider: FakeInfoProvider()
        )
        let entry = RemoteEntry(name: "README.txt", path: "README.txt", kind: .file, size: 10, revision: nil, author: nil, date: nil)

        await viewModel.checkout(entry: entry, baseURL: "file:///repo/trunk", to: URL(fileURLWithPath: "/tmp/readme"), depth: .files)

        let checkoutCalls = await checkoutProvider.recordedCalls()
        let importCalls = await importer.recordedCalls()

        XCTAssertEqual(viewModel.state, .error("checkoutRequiresDirectory"))
        XCTAssertTrue(checkoutCalls.isEmpty)
        XCTAssertTrue(importCalls.isEmpty)
    }

    private func workingCopyRecord(path: String, repoURL: String) -> WorkingCopyRecord {
        WorkingCopyRecord(
            id: UUID(),
            name: URL(fileURLWithPath: path).lastPathComponent,
            localPath: path,
            repoURL: repoURL,
            username: nil,
            addedAt: Date(timeIntervalSince1970: 1),
            lastOpenedAt: Date(timeIntervalSince1970: 1),
            isValid: true,
            revision: Revision(1)
        )
    }
}

private struct CheckoutCall: Equatable, Sendable {
    let url: String
    let destination: URL
    let depth: SvnDepth
    let revision: Revision?
    let ignoreExternals: Bool
    let auth: Credential?

    init(
        url: String,
        destination: URL,
        depth: SvnDepth,
        revision: Revision? = nil,
        ignoreExternals: Bool = false,
        auth: Credential?
    ) {
        self.url = url
        self.destination = destination
        self.depth = depth
        self.revision = revision
        self.ignoreExternals = ignoreExternals
        self.auth = auth
    }
}

private struct WorkspaceImportCall: Equatable, Sendable {
    let localPath: URL
    let username: String?
    let name: String?
}

private actor FakeCheckoutProvider: CheckoutProviding {
    private let error: Error?
    private var calls: [CheckoutCall] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func recordedCalls() -> [CheckoutCall] {
        calls
    }

    func checkout(
        url: String,
        to destination: URL,
        depth: SvnDepth,
        revision: Revision?,
        ignoreExternals: Bool,
        auth: Credential?
    ) async throws {
        calls.append(CheckoutCall(
            url: url,
            destination: destination,
            depth: depth,
            revision: revision,
            ignoreExternals: ignoreExternals,
            auth: auth
        ))
        if let error {
            throw error
        }
    }
}

private actor FakeWorkspaceImporter: WorkspaceImporting {
    private let result: Result<WorkingCopyRecord, Error>
    private var calls: [WorkspaceImportCall] = []

    init(result: Result<WorkingCopyRecord, Error>) {
        self.result = result
    }

    func recordedCalls() -> [WorkspaceImportCall] {
        calls
    }

    func addExistingWorkingCopy(
        localPath: URL,
        infoProvider: any WorkingCopyInfoProviding,
        username: String?,
        name: String?
    ) async throws -> WorkingCopyRecord {
        calls.append(WorkspaceImportCall(localPath: localPath, username: username, name: name))
        return try result.get()
    }
}

private struct FakeInfoProvider: WorkingCopyInfoProviding {
    func info(wc: URL, target: String) async throws -> SvnInfo {
        SvnInfo(path: ".", url: "file:///repo/trunk", repositoryRoot: "file:///repo", revision: Revision(1), kind: "dir")
    }
}
