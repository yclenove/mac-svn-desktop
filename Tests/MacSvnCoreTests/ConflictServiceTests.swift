import Foundation
import XCTest
@testable import MacSvnCore

final class ConflictServiceTests: XCTestCase {
    func testConflictsLoadsInfoForConflictedStatusesAndAbsolutizesSideFiles() async throws {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakeConflictProvider(
            statuses: [
                FileStatus(path: "README.txt", itemStatus: .conflicted, revision: Revision(3), isTreeConflict: false)
            ],
            infos: [
                "README.txt": SvnInfo(
                    path: "README.txt",
                    url: "file:///repo/trunk/README.txt",
                    repositoryRoot: "file:///repo",
                    revision: Revision(3),
                    kind: "file",
                    conflicts: [
                        ConflictInfo(
                            path: "README.txt",
                            kind: .text,
                            baseFile: "README.txt.r1",
                            mineFile: "/tmp/wc/README.txt.mine",
                            theirsFile: "README.txt.r3",
                            treeConflict: nil
                        )
                    ]
                )
            ]
        )
        let service = ConflictService(statusProvider: provider, infoProvider: provider, resolveProvider: provider)

        let conflicts = try await service.conflicts(wc: wc)

        XCTAssertEqual(conflicts, [
            ConflictInfo(
                path: "README.txt",
                kind: .text,
                baseFile: "/tmp/wc/README.txt.r1",
                mineFile: "/tmp/wc/README.txt.mine",
                theirsFile: "/tmp/wc/README.txt.r3",
                treeConflict: nil
            )
        ])
    }

    func testConflictsFallsBackToStatusWhenInfoHasNoConflictNodes() async throws {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakeConflictProvider(
            statuses: [
                FileStatus(path: "tree.txt", itemStatus: .modified, revision: Revision(3), isTreeConflict: true)
            ],
            infos: [
                "tree.txt": SvnInfo(
                    path: "tree.txt",
                    url: "file:///repo/trunk/tree.txt",
                    repositoryRoot: "file:///repo",
                    revision: Revision(3),
                    kind: "file"
                )
            ]
        )
        let service = ConflictService(statusProvider: provider, infoProvider: provider, resolveProvider: provider)

        let conflicts = try await service.conflicts(wc: wc)

        XCTAssertEqual(conflicts, [
            ConflictInfo(
                path: "tree.txt",
                kind: .tree,
                baseFile: nil,
                mineFile: nil,
                theirsFile: nil,
                treeConflict: nil
            )
        ])
    }

    func testLoadTextConflictReadsBaseMineAndTheirs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "base\n".write(to: root.appendingPathComponent("base.txt"), atomically: true, encoding: .utf8)
        try "mine\n".write(to: root.appendingPathComponent("mine.txt"), atomically: true, encoding: .utf8)
        try "theirs\n".write(to: root.appendingPathComponent("theirs.txt"), atomically: true, encoding: .utf8)
        let conflict = ConflictInfo(
            path: "README.txt",
            kind: .text,
            baseFile: root.appendingPathComponent("base.txt").path,
            mineFile: root.appendingPathComponent("mine.txt").path,
            theirsFile: root.appendingPathComponent("theirs.txt").path,
            treeConflict: nil
        )
        let provider = FakeConflictProvider()
        let service = ConflictService(statusProvider: provider, infoProvider: provider, resolveProvider: provider)

        let text = try await service.loadTextConflict(conflict)

        XCTAssertEqual(text.base, "base\n")
        XCTAssertEqual(text.mine, "mine\n")
        XCTAssertEqual(text.theirs, "theirs\n")
    }

    func testSaveResolutionWritesWorkingFileAndResolvesWorking() async throws {
        let wc = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: wc, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: wc) }
        try "conflicted\n".write(to: wc.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        let provider = FakeConflictProvider()
        let service = ConflictService(statusProvider: provider, infoProvider: provider, resolveProvider: provider)
        let conflict = ConflictInfo(path: "README.txt", kind: .text, baseFile: nil, mineFile: nil, theirsFile: nil, treeConflict: nil)

        try await service.saveResolution(conflict, wc: wc, mergedText: "merged\n")
        let resolves = await provider.recordedResolves()

        XCTAssertEqual(try String(contentsOf: wc.appendingPathComponent("README.txt"), encoding: .utf8), "merged\n")
        XCTAssertEqual(resolves, [
            ResolveCall(wc: wc, path: "README.txt", accept: .working)
        ])
    }

    func testResolveWholeFileForwardsAcceptChoice() async throws {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakeConflictProvider()
        let service = ConflictService(statusProvider: provider, infoProvider: provider, resolveProvider: provider)
        let conflict = ConflictInfo(path: "README.txt", kind: .text, baseFile: nil, mineFile: nil, theirsFile: nil, treeConflict: nil)

        try await service.resolveWholeFile(conflict, wc: wc, accept: .mineFull)
        let resolves = await provider.recordedResolves()

        XCTAssertEqual(resolves, [
            ResolveCall(wc: wc, path: "README.txt", accept: .mineFull)
        ])
    }
}

private struct ResolveCall: Equatable, Sendable {
    let wc: URL
    let path: String
    let accept: ResolveAccept
}

private actor FakeConflictProvider: ConflictStatusProviding, ConflictInfoProviding, ConflictResolving {
    private let statuses: [FileStatus]
    private let infos: [String: SvnInfo]
    private var resolves: [ResolveCall] = []

    init(statuses: [FileStatus] = [], infos: [String: SvnInfo] = [:]) {
        self.statuses = statuses
        self.infos = infos
    }

    func recordedResolves() -> [ResolveCall] {
        resolves
    }

    func status(wc: URL) async throws -> [FileStatus] {
        statuses
    }

    func info(wc: URL, target: String) async throws -> SvnInfo {
        guard let info = infos[target] else {
            throw SvnError.parse(detail: "missing fake info for \(target)")
        }

        return info
    }

    func resolve(wc: URL, path: String, accept: ResolveAccept) async throws {
        resolves.append(ResolveCall(wc: wc, path: path, accept: accept))
    }
}
