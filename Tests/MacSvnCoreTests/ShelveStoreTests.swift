import Foundation
import XCTest
@testable import MacSvnCore

final class ShelveStoreTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testCreateSnapshotPersistsMetadataAndPatchText() async throws {
        let root = temporaryRoot()
        let store = ShelveStore(rootDirectory: root)

        let snapshot = try await store.createSnapshot(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            name: "shelved login fix",
            paths: ["Sources/App.swift"],
            patchText: "Index: Sources/App.swift\n+new\n",
            kind: .manual
        )

        XCTAssertEqual(snapshot.name, "shelved login fix")
        XCTAssertEqual(snapshot.wcPath, "/tmp/wc")
        XCTAssertEqual(snapshot.paths, ["Sources/App.swift"])
        XCTAssertEqual(snapshot.kind, .manual)
        XCTAssertEqual(snapshot.patchFileName, "\(snapshot.id.uuidString).patch")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(snapshot.patchRelativePath).path))
        let preview = try await store.preview(snapshot)
        let loaded = try await store.load()
        XCTAssertEqual(preview, "Index: Sources/App.swift\n+new\n")
        XCTAssertEqual(loaded, [snapshot])
    }

    func testDeleteSnapshotRemovesMetadataAndPatchFile() async throws {
        let root = temporaryRoot()
        let store = ShelveStore(rootDirectory: root)
        let snapshot = try await store.createSnapshot(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            name: "temp",
            paths: ["a.txt"],
            patchText: "patch",
            kind: .manual
        )

        try await store.delete(snapshot)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(snapshot.patchRelativePath).path))
    }

    func testSafetySnapshotsKeepMostRecentTwenty() async throws {
        let root = temporaryRoot()
        let store = ShelveStore(rootDirectory: root)
        var createdSnapshots: [ShelveSnapshot] = []

        for index in 0..<22 {
            let snapshot = try await store.createSnapshot(
                wc: URL(fileURLWithPath: "/tmp/wc"),
                name: "safety-\(index)",
                paths: ["a.txt"],
                patchText: "patch-\(index)",
                kind: .safety
            )
            createdSnapshots.append(snapshot)
        }

        let snapshots = try await store.load()
        let safety = snapshots.filter { $0.kind == .safety }
        XCTAssertEqual(safety.count, 20)
        XCTAssertFalse(safety.contains { $0.name == "safety-0" })
        XCTAssertFalse(safety.contains { $0.name == "safety-1" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(createdSnapshots[0].patchRelativePath).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(createdSnapshots[1].patchRelativePath).path))
    }

    private func temporaryRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSvnCoreShelve-\(UUID().uuidString)", isDirectory: true)
        temporaryRoots.append(root)
        return root
    }

}
