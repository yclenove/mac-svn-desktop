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

    func testMigrateRestoresPatchShelvesOfficialThenDeletesLocalSnapshot() async throws {
        let store = ShelveStore(rootDirectory: temporaryRoot())
        let snapshot = try await store.createSnapshot(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            name: "saved",
            paths: ["a.txt"],
            patchText: "patch text",
            kind: .manual
        )
        let events = MigrationEventRecorder()
        let svn = FakeShelveSvnProvider(migrationEvents: events)
        let official = FakeOfficialShelvingProvider(version: .v3, migrationEvents: events)
        let service = ShelveService(store: store, svn: svn, official: official)

        try await service.migrateToOfficial(snapshot)

        let eventsValue = await events.values()
        XCTAssertEqual(eventsValue, ["applyPatch", "officialShelve"])
        let calls = await official.recordedShelveCalls()
        XCTAssertEqual(calls.map(\.name), ["saved"])
        XCTAssertEqual(calls.map(\.paths), [["a.txt"]])
        XCTAssertEqual(calls.map(\.keepLocal), [false])
        let loaded = try await store.load()
        XCTAssertEqual(loaded, [])
    }

    func testMigrationFailureKeepsLocalSnapshotAndSafetySnapshotIsRejected() async throws {
        let store = ShelveStore(rootDirectory: temporaryRoot())
        let manual = try await store.createSnapshot(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            name: "manual",
            paths: ["a.txt"],
            patchText: "patch text",
            kind: .manual
        )
        let safety = try await store.createSnapshot(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            name: "safety",
            paths: ["a.txt"],
            patchText: "patch text",
            kind: .safety
        )
        let official = FakeOfficialShelvingProvider(version: .v2, failShelve: true)
        let service = ShelveService(store: store, svn: FakeShelveSvnProvider(), official: official)

        do {
            try await service.migrateToOfficial(manual)
            XCTFail("Expected official shelve failure")
        } catch {
            XCTAssertEqual(error as? SvnError, .other(code: 200007, stderr: "official failure"))
        }
        let loaded = try await store.load()
        XCTAssertEqual(Set(loaded.map(\.id)), Set([manual.id, safety.id]))

        do {
            try await service.migrateToOfficial(safety)
            XCTFail("Expected safety migration rejection")
        } catch {
            XCTAssertEqual(error as? ShelveServiceError, .cannotMigrateSafetySnapshot)
        }
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

private actor MigrationEventRecorder {
    private var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func values() -> [String] {
        events
    }
}

private struct OfficialShelveCall: Equatable, Sendable {
    let name: String
    let paths: [String]
    let message: String
    let keepLocal: Bool
}

private actor FakeOfficialShelvingProvider: SvnExperimentalShelvingProviding {
    nonisolated let version: SvnShelvingVersion
    private let migrationEvents: MigrationEventRecorder?
    private let failShelve: Bool
    private var shelveCalls: [OfficialShelveCall] = []

    init(
        version: SvnShelvingVersion,
        migrationEvents: MigrationEventRecorder? = nil,
        failShelve: Bool = false
    ) {
        self.version = version
        self.migrationEvents = migrationEvents
        self.failShelve = failShelve
    }

    func recordedShelveCalls() -> [OfficialShelveCall] {
        shelveCalls
    }

    func availability(wc: URL) async -> SvnShelvingAvailability { .available(version) }
    func list(wc: URL) async throws -> [SvnShelf] { [] }

    func shelve(wc: URL, name: String, paths: [String], message: String, keepLocal: Bool) async throws {
        await migrationEvents?.append("officialShelve")
        if failShelve {
            throw SvnError.other(code: 200007, stderr: "official failure")
        }
        shelveCalls.append(OfficialShelveCall(
            name: name,
            paths: paths,
            message: message,
            keepLocal: keepLocal
        ))
    }

    func diff(wc: URL, name: String, version: Int?) async throws -> String { "" }
    func log(wc: URL, name: String) async throws -> String { "" }
    func unshelve(wc: URL, name: String, version: Int?, drop: Bool) async throws {}
    func drop(wc: URL, name: String) async throws {}
}

private actor FakeShelveSvnProvider: ShelveSvnProviding {
    private let diffResults: [String: String]
    private let migrationEvents: MigrationEventRecorder?
    private var revertCalls: [ShelveRevertCall] = []
    private var patchCalls: [ShelvePatchCall] = []

    init(
        diffResults: [String: String] = [:],
        migrationEvents: MigrationEventRecorder? = nil
    ) {
        self.diffResults = diffResults
        self.migrationEvents = migrationEvents
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
        await migrationEvents?.append("applyPatch")
        patchCalls.append(ShelvePatchCall(wc: wc, patchFile: patchFile))
    }
}
