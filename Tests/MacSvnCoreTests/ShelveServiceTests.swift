import Foundation
import XCTest
@testable import MacSvnCore

final class ShelveServiceTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testShelveCreatesPatchSnapshotThenRevertsSelectedPaths() async throws {
        let store = ShelveStore(rootDirectory: temporaryRoot())
        let svn = FakeShelveSvnProvider(diffResults: ["a.txt": "Index: a.txt\n+new\n"])
        let service = ShelveService(store: store, svn: svn)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        let snapshot = try await service.shelve(wc: wc, name: "work in progress", paths: ["a.txt"])
        let preview = try await store.preview(snapshot)
        let revertCalls = await svn.recordedRevertCalls()

        XCTAssertEqual(snapshot.kind, .manual)
        XCTAssertEqual(preview, "Index: a.txt\n+new\n")
        XCTAssertEqual(revertCalls, [
            ShelveRevertCall(wc: wc, paths: ["a.txt"], recursive: true)
        ])
    }

    func testShelveRejectsEmptyDiffBeforeRevert() async throws {
        let store = ShelveStore(rootDirectory: temporaryRoot())
        let svn = FakeShelveSvnProvider(diffResults: ["a.txt": ""])
        let service = ShelveService(store: store, svn: svn)

        do {
            _ = try await service.shelve(
                wc: URL(fileURLWithPath: "/tmp/wc"),
                name: "empty",
                paths: ["a.txt"]
            )
            XCTFail("Expected empty patch")
        } catch let error as ShelveServiceError {
            XCTAssertEqual(error, .emptyPatch)
        } catch {
            XCTFail("Expected ShelveServiceError, got \(error)")
        }

        let revertCalls = await svn.recordedRevertCalls()
        XCTAssertTrue(revertCalls.isEmpty)
        let loaded = try await store.load()
        XCTAssertEqual(loaded, [])
    }

    func testSafetySnapshotStoresPatchWithoutReverting() async throws {
        let store = ShelveStore(rootDirectory: temporaryRoot())
        let svn = FakeShelveSvnProvider(diffResults: ["a.txt": "Index: a.txt\n+new\n"])
        let service = ShelveService(store: store, svn: svn)

        let snapshot = try await service.createSafetySnapshot(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            name: "before revert",
            paths: ["a.txt"]
        )

        XCTAssertEqual(snapshot.kind, .safety)
        let preview = try await store.preview(snapshot)
        XCTAssertEqual(preview, "Index: a.txt\n+new\n")
        let revertCalls = await svn.recordedRevertCalls()
        XCTAssertTrue(revertCalls.isEmpty)
    }

    func testRestoreAppliesPatchAndOptionallyDeletesManualSnapshot() async throws {
        let store = ShelveStore(rootDirectory: temporaryRoot())
        let snapshot = try await store.createSnapshot(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            name: "saved",
            paths: ["a.txt"],
            patchText: "Index: a.txt\n+new\n",
            kind: .manual
        )
        let svn = FakeShelveSvnProvider()
        let service = ShelveService(store: store, svn: svn)

        try await service.restore(snapshot, deleteAfterRestore: true)

        let patchCalls = await svn.recordedPatchCalls()
        XCTAssertEqual(patchCalls.map(\.wc), [URL(fileURLWithPath: "/tmp/wc")])
        XCTAssertEqual(patchCalls.map(\.patchFile.lastPathComponent), [snapshot.patchFileName])
        let loaded = try await store.load()
        XCTAssertEqual(loaded, [])
    }

    func testDeleteAndPreviewForwardToStore() async throws {
        let store = ShelveStore(rootDirectory: temporaryRoot())
        let snapshot = try await store.createSnapshot(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            name: "saved",
            paths: ["a.txt"],
            patchText: "patch text",
            kind: .manual
        )
        let service = ShelveService(store: store, svn: FakeShelveSvnProvider())

        let preview = try await service.preview(snapshot)
        XCTAssertEqual(preview, "patch text")
        try await service.delete(snapshot)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, [])
    }

    private func temporaryRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSvnCoreShelveService-\(UUID().uuidString)", isDirectory: true)
        temporaryRoots.append(root)
        return root
    }
}

private struct ShelveRevertCall: Equatable, Sendable {
    let wc: URL
    let paths: [String]
    let recursive: Bool
}

private struct ShelvePatchCall: Equatable, Sendable {
    let wc: URL
    let patchFile: URL
}

private actor FakeShelveSvnProvider: ShelveSvnProviding {
    private let diffResults: [String: String]
    private var revertCalls: [ShelveRevertCall] = []
    private var patchCalls: [ShelvePatchCall] = []

    init(diffResults: [String: String] = [:]) {
        self.diffResults = diffResults
    }

    func recordedRevertCalls() -> [ShelveRevertCall] {
        revertCalls
    }

    func recordedPatchCalls() -> [ShelvePatchCall] {
        patchCalls
    }

    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        diffResults[target] ?? ""
    }

    func revert(wc: URL, paths: [String], recursive: Bool) async throws {
        revertCalls.append(ShelveRevertCall(wc: wc, paths: paths, recursive: recursive))
    }

    func applyPatch(wc: URL, patchFile: URL) async throws {
        patchCalls.append(ShelvePatchCall(wc: wc, patchFile: patchFile))
    }
}
