import Foundation
import XCTest
@testable import MacSvnCore

final class BranchListServiceTests: XCTestCase {
    func testBranchLayoutURLResolverBuildsStandardUrlsFromRepositoryRoot() {
        let layout = BranchLayout()

        XCTAssertEqual(
            BranchListURLResolver.url(repositoryRoot: "file:///repo", path: layout.trunk),
            "file:///repo/trunk"
        )
        XCTAssertEqual(
            BranchListURLResolver.url(repositoryRoot: "file:///repo/", path: layout.branches),
            "file:///repo/branches"
        )
        XCTAssertEqual(
            BranchListURLResolver.url(repositoryRoot: "file:///repo", path: "release/tags"),
            "file:///repo/release/tags"
        )
    }

    func testBranchLayoutURLResolverKeepsAbsoluteLayoutPaths() {
        XCTAssertEqual(
            BranchListURLResolver.url(repositoryRoot: "file:///repo", path: "/custom/branches"),
            "file:///repo/custom/branches"
        )
    }

    func testBranchListProviderListsTrunkBranchesAndTagsWithImmediateDepth() async throws {
        let listProvider = FakeBranchRepoListProvider(results: [
            "file:///repo/trunk": .success([
                RemoteEntry(
                    name: "README.txt",
                    path: "README.txt",
                    kind: .file,
                    size: 4,
                    revision: Revision(2),
                    author: "a",
                    date: nil
                )
            ]),
            "file:///repo/branches": .success([
                RemoteEntry(
                    name: "feature-one",
                    path: "feature-one",
                    kind: .directory,
                    size: nil,
                    revision: Revision(3),
                    author: "b",
                    date: nil
                ),
                RemoteEntry(
                    name: "note.txt",
                    path: "note.txt",
                    kind: .file,
                    size: 1,
                    revision: Revision(4),
                    author: "c",
                    date: nil
                )
            ]),
            "file:///repo/tags": .success([
                RemoteEntry(
                    name: "v1.0",
                    path: "v1.0",
                    kind: .directory,
                    size: nil,
                    revision: Revision(5),
                    author: "d",
                    date: nil
                )
            ])
        ])
        let auth = Credential(username: "u", password: "p")

        let branchList = try await BranchListService(listProvider: listProvider).branches(
            repositoryRoot: "file:///repo",
            layout: BranchLayout(),
            auth: auth
        )
        let calls = await listProvider.recordedCalls()

        XCTAssertEqual(branchList.trunk?.url, "file:///repo/trunk")
        XCTAssertEqual(branchList.trunk?.kind, .trunk)
        XCTAssertEqual(branchList.trunk?.revision, Revision(2))
        XCTAssertEqual(branchList.branches.map(\.name), ["feature-one"])
        XCTAssertEqual(branchList.branches.map(\.url), ["file:///repo/branches/feature-one"])
        XCTAssertEqual(branchList.tags.map(\.name), ["v1.0"])
        XCTAssertEqual(calls, [
            BranchRepoListCall(url: "file:///repo/trunk", depth: .immediates, auth: auth),
            BranchRepoListCall(url: "file:///repo/branches", depth: .immediates, auth: auth),
            BranchRepoListCall(url: "file:///repo/tags", depth: .immediates, auth: auth)
        ])
    }

    func testMissingTrunkStillReturnsBranchesAndTags() async throws {
        let listProvider = FakeBranchRepoListProvider(results: [
            "file:///repo/trunk": .failure(SvnError.environment(detail: "missing")),
            "file:///repo/branches": .success([
                RemoteEntry(name: "dev", path: "dev", kind: .directory, size: nil, revision: nil, author: nil, date: nil)
            ]),
            "file:///repo/tags": .success([])
        ])

        let branchList = try await BranchListService(listProvider: listProvider).branches(
            repositoryRoot: "file:///repo",
            layout: BranchLayout(),
            auth: nil
        )

        XCTAssertNil(branchList.trunk)
        XCTAssertEqual(branchList.branches.map(\.name), ["dev"])
        XCTAssertEqual(branchList.tags, [])
    }
}

private struct BranchRepoListCall: Equatable, Sendable {
    let url: String
    let depth: SvnDepth
    let auth: Credential?
}

private actor FakeBranchRepoListProvider: BranchRepositoryListing {
    private let results: [String: Result<[RemoteEntry], Error>]
    private var calls: [BranchRepoListCall] = []

    init(results: [String: Result<[RemoteEntry], Error>]) {
        self.results = results
    }

    func recordedCalls() -> [BranchRepoListCall] {
        calls
    }

    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry] {
        calls.append(BranchRepoListCall(url: url, depth: depth, auth: auth))
        return try results[url, default: .success([])].get()
    }
}
