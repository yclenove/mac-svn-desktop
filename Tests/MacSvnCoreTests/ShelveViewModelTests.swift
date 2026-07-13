import Foundation
import XCTest
@testable import MacSvnCore

final class ShelveViewModelTests: XCTestCase {
    @MainActor
    func testLoadPreviewRestoreAndDeleteUpdateStateAndSnapshots() async {
        let first = shelveSnapshot(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "saved")
        let second = shelveSnapshot(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "other")
        let provider = FakeShelveProvider(
            snapshots: [first, second],
            previewText: "Index: a.txt\n+new\n"
        )
        let viewModel = ShelveViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            shelveProvider: provider
        )

        await viewModel.load()
        await viewModel.preview(first)
        await viewModel.restore(first, deleteAfterRestore: true)
        await viewModel.delete(second)

        XCTAssertEqual(viewModel.state, .completed(.delete))
        XCTAssertEqual(viewModel.snapshots, [])
        XCTAssertEqual(viewModel.previewText, "Index: a.txt\n+new\n")
        let restoreCalls = await provider.recordedRestoreCalls()
        let deleteCalls = await provider.recordedDeleteCalls()
        XCTAssertEqual(restoreCalls, [
            ShelveRestoreCall(snapshot: first, deleteAfterRestore: true)
        ])
        XCTAssertEqual(deleteCalls, [second])
    }

    @MainActor
    func testShelveAndSafetySnapshotValidateInputCallProviderAndReload() async {
        let manual = shelveSnapshot(name: "saved", kind: .manual)
        let safety = shelveSnapshot(name: "before merge", kind: .safety)
        let provider = FakeShelveProvider(shelveResult: manual, safetyResult: safety)
        let workingCopy = URL(fileURLWithPath: "/tmp/wc")
        let viewModel = ShelveViewModel(workingCopy: workingCopy, shelveProvider: provider)

        await viewModel.shelve(name: " ", paths: ["a.txt"])
        XCTAssertEqual(viewModel.state, .error("emptyShelveName"))

        await viewModel.shelve(name: "saved", paths: [])
        XCTAssertEqual(viewModel.state, .error("noSelectedPaths"))
        let emptyShelveCalls = await provider.recordedShelveCalls()
        XCTAssertTrue(emptyShelveCalls.isEmpty)

        await viewModel.shelve(name: "saved", paths: ["a.txt"])
        await viewModel.createSafetySnapshot(name: "before merge", paths: ["a.txt"])

        XCTAssertEqual(viewModel.state, .completed(.safetySnapshot))
        XCTAssertEqual(viewModel.snapshots, [manual, safety])
        let shelveCalls = await provider.recordedShelveCalls()
        let safetyCalls = await provider.recordedSafetyCalls()
        XCTAssertEqual(shelveCalls, [
            ShelveCreateCall(wc: workingCopy, name: "saved", paths: ["a.txt"])
        ])
        XCTAssertEqual(safetyCalls, [
            ShelveCreateCall(wc: workingCopy, name: "before merge", paths: ["a.txt"])
        ])
    }

    @MainActor
    func testProviderFailureStoresError() async {
        let provider = FakeShelveProvider(loadError: SvnError.network(detail: "offline"))
        let viewModel = ShelveViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            shelveProvider: provider
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state, .error(String(describing: SvnError.network(detail: "offline"))))
        XCTAssertEqual(viewModel.snapshots, [])
    }

    @MainActor
    func testLoadAndOfficialOperationsExposeShelfState() async {
        let shelf = SvnShelf(
            name: "official",
            latestVersion: 3,
            pathCount: 2,
            ageSummary: "2 minutes ago",
            message: "review"
        )
        let provider = FakeShelveProvider(
            officialAvailability: .available(.v3),
            officialShelves: [shelf],
            officialDiffText: "diff",
            officialLogText: "log"
        )
        let viewModel = ShelveViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            shelveProvider: provider
        )

        await viewModel.load()
        await viewModel.officialDiff(shelf)
        await viewModel.officialLog(shelf)
        await viewModel.officialUnshelve(shelf, version: 3, drop: true)
        await viewModel.officialDrop(shelf)

        XCTAssertEqual(viewModel.officialAvailability, .available(.v3))
        XCTAssertEqual(viewModel.officialShelves, [shelf])
        XCTAssertEqual(viewModel.officialDiffText, "diff")
        XCTAssertEqual(viewModel.officialLogText, "log")
        XCTAssertEqual(viewModel.state, .completed(.officialDrop))
        let calls = await provider.recordedOfficialCalls()
        XCTAssertEqual(calls, [
            "diff:official:3",
            "log:official",
            "unshelve:official:3:true",
            "drop:official"
        ])
    }

    @MainActor
    func testMigrateLocalSnapshotUpdatesStateThroughProvider() async {
        let snapshot = shelveSnapshot(name: "manual")
        let provider = FakeShelveProvider()
        let viewModel = ShelveViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            shelveProvider: provider
        )

        await viewModel.migrateToOfficial(snapshot)

        XCTAssertEqual(viewModel.state, .completed(.migrate))
        let migrated = await provider.recordedMigrationSnapshots()
        XCTAssertEqual(migrated, [snapshot])
    }
}

private struct ShelveCreateCall: Equatable, Sendable {
    let wc: URL
    let name: String
    let paths: [String]
}

private struct ShelveRestoreCall: Equatable, Sendable {
    let snapshot: ShelveSnapshot
    let deleteAfterRestore: Bool
}

private actor FakeShelveProvider: ShelveProviding {
    private var snapshots: [ShelveSnapshot]
    private let previewText: String
    private let shelveResult: ShelveSnapshot?
    private let safetyResult: ShelveSnapshot?
    private let loadError: Error?
    private var shelveCalls: [ShelveCreateCall] = []
    private var safetyCalls: [ShelveCreateCall] = []
    private var restoreCalls: [ShelveRestoreCall] = []
    private var deleteCalls: [ShelveSnapshot] = []
    private let officialAvailabilityResult: SvnShelvingAvailability
    private let officialShelvesResult: [SvnShelf]
    private let officialDiffText: String
    private let officialLogText: String
    private var officialCalls: [String] = []
    private var migrationSnapshots: [ShelveSnapshot] = []

    init(
        snapshots: [ShelveSnapshot] = [],
        previewText: String = "",
        shelveResult: ShelveSnapshot? = nil,
        safetyResult: ShelveSnapshot? = nil,
        loadError: Error? = nil,
        officialAvailability: SvnShelvingAvailability = .unavailable(.v3, reason: "not configured"),
        officialShelves: [SvnShelf] = [],
        officialDiffText: String = "",
        officialLogText: String = ""
    ) {
        self.snapshots = snapshots
        self.previewText = previewText
        self.shelveResult = shelveResult
        self.safetyResult = safetyResult
        self.loadError = loadError
        self.officialAvailabilityResult = officialAvailability
        self.officialShelvesResult = officialShelves
        self.officialDiffText = officialDiffText
        self.officialLogText = officialLogText
    }

    func load() async throws -> [ShelveSnapshot] {
        if let loadError {
            throw loadError
        }

        return snapshots
    }

    func shelve(wc: URL, name: String, paths: [String]) async throws -> ShelveSnapshot {
        let snapshot = shelveResult ?? shelveSnapshot(name: name, paths: paths, kind: .manual)
        shelveCalls.append(ShelveCreateCall(wc: wc, name: name, paths: paths))
        snapshots.append(snapshot)
        return snapshot
    }

    func createSafetySnapshot(wc: URL, name: String, paths: [String]) async throws -> ShelveSnapshot {
        let snapshot = safetyResult ?? shelveSnapshot(name: name, paths: paths, kind: .safety)
        safetyCalls.append(ShelveCreateCall(wc: wc, name: name, paths: paths))
        snapshots.append(snapshot)
        return snapshot
    }

    func preview(_ snapshot: ShelveSnapshot) async throws -> String {
        previewText
    }

    func restore(_ snapshot: ShelveSnapshot, deleteAfterRestore: Bool) async throws {
        restoreCalls.append(ShelveRestoreCall(snapshot: snapshot, deleteAfterRestore: deleteAfterRestore))
        if deleteAfterRestore {
            snapshots.removeAll { $0.id == snapshot.id }
        }
    }

    func delete(_ snapshot: ShelveSnapshot) async throws {
        deleteCalls.append(snapshot)
        snapshots.removeAll { $0.id == snapshot.id }
    }

    func recordedShelveCalls() -> [ShelveCreateCall] {
        shelveCalls
    }

    func recordedSafetyCalls() -> [ShelveCreateCall] {
        safetyCalls
    }

    func recordedRestoreCalls() -> [ShelveRestoreCall] {
        restoreCalls
    }

    func recordedDeleteCalls() -> [ShelveSnapshot] {
        deleteCalls
    }

    func officialAvailability(wc: URL) async -> SvnShelvingAvailability {
        officialAvailabilityResult
    }

    func officialShelves(wc: URL) async throws -> [SvnShelf] {
        officialShelvesResult
    }

    func officialShelve(wc: URL, name: String, paths: [String], message: String, keepLocal: Bool) async throws {}

    func officialDiff(wc: URL, name: String, version: Int?) async throws -> String {
        let versionText = version.map(String.init) ?? "nil"
        officialCalls.append("diff:\(name):\(versionText)")
        return officialDiffText
    }

    func officialLog(wc: URL, name: String) async throws -> String {
        officialCalls.append("log:\(name)")
        return officialLogText
    }

    func officialUnshelve(wc: URL, name: String, version: Int?, drop: Bool) async throws {
        let versionText = version.map(String.init) ?? "nil"
        officialCalls.append("unshelve:\(name):\(versionText):\(drop)")
    }

    func officialDrop(wc: URL, name: String) async throws {
        officialCalls.append("drop:\(name)")
    }

    func recordedOfficialCalls() -> [String] {
        officialCalls
    }

    func migrateToOfficial(_ snapshot: ShelveSnapshot) async throws {
        migrationSnapshots.append(snapshot)
    }

    func recordedMigrationSnapshots() -> [ShelveSnapshot] {
        migrationSnapshots
    }
}

private func shelveSnapshot(
    id: UUID = UUID(),
    name: String,
    paths: [String] = ["a.txt"],
    kind: ShelveKind = .manual
) -> ShelveSnapshot {
    ShelveSnapshot(
        id: id,
        wcPath: "/tmp/wc",
        name: name,
        paths: paths,
        patchRelativePath: "\(kind.rawValue)/\(id.uuidString).patch",
        createdAt: Date(timeIntervalSince1970: 1),
        kind: kind
    )
}
