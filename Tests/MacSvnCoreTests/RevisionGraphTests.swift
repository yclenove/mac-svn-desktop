import Foundation
import XCTest
@testable import MacSvnCore

final class RevisionGraphPathClassifierTests: XCTestCase {
    func testClassifiesConfiguredTrunkBranchAndTagPatternsAndReturnsRootPath() {
        let settings = RevisionGraphSettings(
            trunkPatterns: ["trunk/**"],
            branchPatterns: ["branches/*/**"],
            tagPatterns: ["tags/*/**"]
        )
        let classifier = RevisionGraphPathClassifier(settings: settings)

        XCTAssertEqual(
            classifier.classify("/trunk/Sources/App.swift"),
            RevisionGraphPathMatch(rootPath: "/trunk", category: .trunk)
        )
        XCTAssertEqual(
            classifier.classify("/branches/feature/Sources/App.swift"),
            RevisionGraphPathMatch(rootPath: "/branches/feature", category: .branch)
        )
        XCTAssertEqual(
            classifier.classify("/tags/v1.0/README.md"),
            RevisionGraphPathMatch(rootPath: "/tags/v1.0", category: .tag)
        )
    }

    func testUnmatchedPathIsUnclassifiedWithoutPretendingItIsATrunk() {
        let classifier = RevisionGraphPathClassifier(settings: RevisionGraphSettings())

        XCTAssertNil(classifier.classify("/vendor/lib/file.txt"))
    }
}

final class RevisionGraphBuilderTests: XCTestCase {
    func testBuildsContinuityAndCopyEdgesFromVerboseLog() {
        let entries = [
            graphLogEntry(
                revision: 1,
                path: "/trunk/README.md",
                action: .added
            ),
            graphLogEntry(
                revision: 2,
                path: "/branches/feature/README.md",
                action: .added,
                copyFromPath: "/trunk",
                copyFromRevision: 1
            ),
            graphLogEntry(
                revision: 3,
                path: "/branches/feature/README.md",
                action: .modified
            )
        ]

        let snapshot = RevisionGraphBuilder.build(
            entries: entries,
            settings: RevisionGraphSettings(
                trunkPatterns: ["trunk/**"],
                branchPatterns: ["branches/*/**"],
                tagPatterns: ["tags/*/**"]
            )
        )

        XCTAssertEqual(snapshot.nodes.map(\.id), [
            "/trunk@1",
            "/branches/feature@2",
            "/branches/feature@3"
        ])
        XCTAssertTrue(snapshot.edges.contains {
            $0.kind == .copy && $0.sourceID == "/trunk@1" && $0.targetID == "/branches/feature@2"
        })
        XCTAssertTrue(snapshot.edges.contains {
            $0.kind == .history && $0.sourceID == "/branches/feature@2" && $0.targetID == "/branches/feature@3"
        })
        XCTAssertEqual(snapshot.nodes.first(where: { $0.id == "/branches/feature@2" })?.category, .branch)
    }

    func testPruningCanHideTagsAndUnclassifiedNodesWhileKeepingEdgesValid() {
        let entries = [
            graphLogEntry(revision: 1, path: "/trunk/file.txt", action: .modified),
            graphLogEntry(revision: 2, path: "/tags/v1/file.txt", action: .added),
            graphLogEntry(revision: 3, path: "/vendor/file.txt", action: .modified)
        ]
        let snapshot = RevisionGraphBuilder.build(
            entries: entries,
            settings: RevisionGraphSettings(
                trunkPatterns: ["trunk/**"],
                branchPatterns: ["branches/*/**"],
                tagPatterns: ["tags/*/**"]
            )
        )

        let pruned = snapshot.pruned(
            by: RevisionGraphPruning(
                includeTags: false,
                includeUnclassified: false
            )
        )

        XCTAssertEqual(pruned.nodes.map(\.category), [.trunk])
        XCTAssertTrue(pruned.edges.allSatisfy { edge in
            pruned.nodes.contains { $0.id == edge.sourceID }
                && pruned.nodes.contains { $0.id == edge.targetID }
        })
    }
}

final class RevisionGraphNodeActionPolicyTests: XCTestCase {
    func testNodeActionsProvideLogCheckoutBlameAndDiffIntents() {
        let node = RevisionGraphNode(
            path: "/branches/feature one",
            revision: Revision(9),
            category: .branch,
            author: "yangchao",
            date: nil,
            message: "feature",
            changedPaths: [
                ChangedPath(
                    path: "/branches/feature one/Sources/App.swift",
                    action: .modified,
                    kind: "file",
                    copyFromPath: nil,
                    copyFromRevision: nil
                )
            ]
        )
        let root = "https://svn.example/repo"

        XCTAssertEqual(
            RevisionGraphNodeActionPolicy.intent(for: .log, node: node, repositoryRoot: root),
            .log(url: "https://svn.example/repo/branches/feature%20one", revision: Revision(9))
        )
        XCTAssertEqual(
            RevisionGraphNodeActionPolicy.intent(for: .checkout, node: node, repositoryRoot: root),
            .checkout(url: "https://svn.example/repo/branches/feature%20one", revision: Revision(9))
        )
        XCTAssertEqual(
            RevisionGraphNodeActionPolicy.intent(for: .blame, node: node, repositoryRoot: root),
            .blame(
                url: "https://svn.example/repo/branches/feature%20one/Sources/App.swift",
                revision: Revision(9)
            )
        )
        XCTAssertEqual(
            RevisionGraphNodeActionPolicy.intent(for: .diff, node: node, repositoryRoot: root),
            .diff(nodeID: node.id)
        )
    }
}

@MainActor
final class RevisionGraphViewModelTests: XCTestCase {
    func testLoadInitialAndMoreFetchRemoteRepositoryLogAndBuildGraph() async {
        let provider = FakeRevisionGraphProvider(
            info: SvnInfo(
                path: "/tmp/wc",
                url: "https://svn.example/repo/trunk",
                repositoryRoot: "https://svn.example/repo",
                revision: Revision(3),
                kind: "dir"
            ),
            pages: [
                [graphLogEntry(revision: 3, path: "/trunk/file.txt", action: .modified),
                 graphLogEntry(revision: 2, path: "/trunk/file.txt", action: .modified)],
                [graphLogEntry(revision: 1, path: "/trunk/file.txt", action: .added)]
            ]
        )
        let viewModel = RevisionGraphViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            batchSize: 2,
            settings: RevisionGraphSettings(
                trunkPatterns: ["trunk/**"],
                branchPatterns: ["branches/*/**"],
                tagPatterns: ["tags/*/**"]
            ),
            provider: provider
        )

        await viewModel.loadInitial()
        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.entries.map(\.revision.value), [3, 2])
        XCTAssertTrue(viewModel.hasMore)

        await viewModel.loadMore()
        XCTAssertEqual(viewModel.entries.map(\.revision.value), [3, 2, 1])
        XCTAssertFalse(viewModel.hasMore)
        XCTAssertEqual(viewModel.repositoryRoot, "https://svn.example/repo")
    }

    func testDiffForCopyNodeComparesCopySourceToCreatedBranch() async {
        let provider = FakeRevisionGraphProvider(
            info: SvnInfo(
                path: "/tmp/wc",
                url: "https://svn.example/repo/trunk",
                repositoryRoot: "https://svn.example/repo",
                revision: Revision(2),
                kind: "dir"
            ),
            pages: [[
                graphLogEntry(
                    revision: 2,
                    path: "/branches/feature/file.txt",
                    action: .added,
                    copyFromPath: "/trunk/file.txt",
                    copyFromRevision: 1
                ),
                graphLogEntry(revision: 1, path: "/trunk/file.txt", action: .added)
            ]],
            diffResult: "@@ copy diff"
        )
        let viewModel = RevisionGraphViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            batchSize: 10,
            settings: RevisionGraphSettings(),
            provider: provider
        )
        await viewModel.loadInitial()

        await viewModel.loadDiff(for: "/branches/feature@2")

        XCTAssertEqual(viewModel.diffState, .loaded)
        XCTAssertEqual(viewModel.diffText, "@@ copy diff")
        let calls = await provider.recordedDiffCalls()
        XCTAssertEqual(calls, [
            RevisionGraphDiffCall(
                oldURL: "https://svn.example/repo/trunk",
                oldRevision: Revision(1),
                newURL: "https://svn.example/repo/branches/feature",
                newRevision: Revision(2)
            )
        ])
    }

    func testSlowerEarlierDiffCannotOverwriteLatestNodeDiff() async {
        let provider = FakeRevisionGraphProvider(
            info: SvnInfo(
                path: "/tmp/wc",
                url: "https://svn.example/repo/trunk",
                repositoryRoot: "https://svn.example/repo",
                revision: Revision(3),
                kind: "dir"
            ),
            pages: [[
                graphLogEntry(revision: 3, path: "/trunk/file.txt", action: .modified),
                graphLogEntry(revision: 2, path: "/trunk/file.txt", action: .modified),
                graphLogEntry(revision: 1, path: "/trunk/file.txt", action: .added)
            ]],
            diffResultsByRevision: [2: "older", 3: "latest"],
            diffDelaysByRevision: [2: 100_000_000, 3: 1_000_000]
        )
        let viewModel = RevisionGraphViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            batchSize: 10,
            settings: RevisionGraphSettings(),
            provider: provider
        )
        await viewModel.loadInitial()

        let earlier = Task { await viewModel.loadDiff(for: "/trunk@2") }
        await Task.yield()
        await viewModel.loadDiff(for: "/trunk@3")
        await earlier.value

        XCTAssertEqual(viewModel.diffState, .loaded)
        XCTAssertEqual(viewModel.diffText, "latest")
    }
}

private actor FakeRevisionGraphProvider: RevisionGraphProviding {
    let infoResult: SvnInfo
    var pages: [[LogEntry]]
    let diffResult: String
    let diffResultsByRevision: [Int: String]
    let diffDelaysByRevision: [Int: UInt64]
    var diffCalls: [RevisionGraphDiffCall] = []

    init(
        info: SvnInfo,
        pages: [[LogEntry]],
        diffResult: String = "",
        diffResultsByRevision: [Int: String] = [:],
        diffDelaysByRevision: [Int: UInt64] = [:]
    ) {
        self.infoResult = info
        self.pages = pages
        self.diffResult = diffResult
        self.diffResultsByRevision = diffResultsByRevision
        self.diffDelaysByRevision = diffDelaysByRevision
    }

    func recordedDiffCalls() -> [RevisionGraphDiffCall] { diffCalls }

    func info(wc: URL, target: String) async throws -> SvnInfo {
        infoResult
    }

    func remoteLogFromHead(
        url: String,
        batch: Int,
        verbose: Bool,
        auth: Credential?
    ) async throws -> [LogEntry] {
        pages.removeFirst()
    }

    func remoteLog(
        url: String,
        from: Revision,
        batch: Int,
        verbose: Bool,
        auth: Credential?
    ) async throws -> [LogEntry] {
        pages.removeFirst()
    }

    func repositoryDiff(
        wc: URL,
        oldURL: String,
        oldRevision: Revision,
        newURL: String,
        newRevision: Revision,
        auth: Credential?
    ) async throws -> String {
        _ = wc
        _ = auth
        if let delay = diffDelaysByRevision[newRevision.value] {
            try await Task.sleep(nanoseconds: delay)
        }
        diffCalls.append(RevisionGraphDiffCall(
            oldURL: oldURL,
            oldRevision: oldRevision,
            newURL: newURL,
            newRevision: newRevision
        ))
        return diffResultsByRevision[newRevision.value] ?? diffResult
    }
}

private struct RevisionGraphDiffCall: Equatable, Sendable {
    let oldURL: String
    let oldRevision: Revision
    let newURL: String
    let newRevision: Revision
}

private func graphLogEntry(
    revision: Int,
    path: String,
    action: ChangedPathAction,
    copyFromPath: String? = nil,
    copyFromRevision: Int? = nil
) -> LogEntry {
    LogEntry(
        revision: Revision(revision),
        author: "yangchao",
        date: nil,
        message: "r\(revision)",
        changedPaths: [
            ChangedPath(
                path: path,
                action: action,
                kind: "file",
                copyFromPath: copyFromPath,
                copyFromRevision: copyFromRevision.map { Revision($0) }
            )
        ]
    )
}
