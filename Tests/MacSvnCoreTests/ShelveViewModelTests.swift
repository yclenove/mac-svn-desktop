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

    @MainActor
    func testLoadStaysLoadingUntilOfficialRefreshCompletes() async {
        let snapshot = shelveSnapshot(name: "local")
        let shelf = SvnShelf(
            name: "official",
            latestVersion: 1,
            pathCount: 1,
            ageSummary: "now",
            message: nil
        )
        let officialGate = AsyncGate()
        let provider = FakeShelveProvider(
            snapshots: [snapshot],
            officialAvailability: .available(.v3),
            officialShelves: [shelf],
            officialGate: officialGate
        )
        let viewModel = ShelveViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            shelveProvider: provider
        )

        let loadTask = Task { await viewModel.load() }
        let didEnterOfficialRefresh = await officialGate.waitUntilEntered()
        XCTAssertTrue(didEnterOfficialRefresh)

        XCTAssertEqual(viewModel.snapshots, [snapshot])
        XCTAssertEqual(viewModel.state, .loading)

        await officialGate.open()
        await loadTask.value
        XCTAssertEqual(viewModel.officialShelves, [shelf])
        XCTAssertEqual(viewModel.state, .loaded)
    }

    @MainActor
    func testMigrationStaysRunningUntilOfficialRefreshCompletes() async {
        let snapshot = shelveSnapshot(name: "manual")
        let refreshedSnapshot = shelveSnapshot(name: "remaining")
        let officialGate = AsyncGate()
        let provider = FakeShelveProvider(
            snapshots: [refreshedSnapshot],
            officialAvailability: .available(.v3),
            officialGate: officialGate
        )
        let viewModel = ShelveViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            shelveProvider: provider
        )

        let migrationTask = Task { await viewModel.migrateToOfficial(snapshot) }
        let didEnterOfficialRefresh = await officialGate.waitUntilEntered()
        XCTAssertTrue(didEnterOfficialRefresh)

        XCTAssertEqual(viewModel.snapshots, [refreshedSnapshot])
        XCTAssertEqual(viewModel.state, .running(.migrate))

        await officialGate.open()
        await migrationTask.value
        XCTAssertEqual(viewModel.state, .completed(.migrate))
    }

    @MainActor
    func testOlderLoadCannotCompleteWhileNewerLoadStillRefreshesOfficialShelves() async {
        let firstGate = AsyncGate()
        let secondGate = AsyncGate()
        let provider = FakeShelveProvider(
            officialAvailability: .available(.v3),
            officialGates: [firstGate, secondGate]
        )
        let viewModel = ShelveViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            shelveProvider: provider
        )

        let firstLoad = Task { await viewModel.load() }
        let didEnterFirst = await firstGate.waitUntilEntered()
        XCTAssertTrue(didEnterFirst)

        let secondLoad = Task { await viewModel.load() }
        let didEnterSecond = await secondGate.waitUntilEntered()
        XCTAssertTrue(didEnterSecond)

        await firstGate.open()
        await firstLoad.value
        XCTAssertEqual(viewModel.state, .loading)

        await secondGate.open()
        await secondLoad.value
        XCTAssertEqual(viewModel.state, .loaded)
    }

    @MainActor
    func testOlderMigrationCannotOverwriteNewerPreviewState() async {
        let snapshot = shelveSnapshot(name: "manual")
        let officialGate = AsyncGate()
        let provider = FakeShelveProvider(
            previewText: "preview from newer operation",
            officialAvailability: .available(.v3),
            officialGate: officialGate
        )
        let viewModel = ShelveViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            shelveProvider: provider
        )

        let migrationTask = Task { await viewModel.migrateToOfficial(snapshot) }
        let didEnterOfficialRefresh = await officialGate.waitUntilEntered()
        XCTAssertTrue(didEnterOfficialRefresh)

        await viewModel.preview(snapshot)
        XCTAssertEqual(viewModel.state, .completed(.preview))

        await officialGate.open()
        await migrationTask.value
        XCTAssertEqual(viewModel.state, .completed(.preview))
    }

    @MainActor
    func testOlderLoadCannotCommitStaleSnapshotsAfterNewerLoadCompletes() async {
        let staleSnapshot = shelveSnapshot(name: "stale")
        let currentSnapshot = shelveSnapshot(name: "current")
        let staleLoadGate = AsyncGate()
        let provider = FakeShelveProvider(
            snapshotLoadOutcomes: [
                .success([staleSnapshot]),
                .success([currentSnapshot]),
            ],
            snapshotLoadGates: [staleLoadGate, nil]
        )
        let viewModel = ShelveViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            shelveProvider: provider
        )

        let staleLoad = Task { await viewModel.load() }
        let didBlockStaleLoad = await staleLoadGate.waitUntilEntered()
        XCTAssertTrue(didBlockStaleLoad)

        await viewModel.load()
        XCTAssertEqual(viewModel.snapshots, [currentSnapshot])
        XCTAssertEqual(viewModel.state, .loaded)

        await staleLoadGate.open()
        await staleLoad.value
        XCTAssertEqual(viewModel.snapshots, [currentSnapshot])
        XCTAssertEqual(viewModel.state, .loaded)
    }

    @MainActor
    func testOlderMigrationSnapshotFailureCannotOverwriteNewerPreviewStateOrSnapshots() async {
        let baselineSnapshot = shelveSnapshot(name: "baseline")
        let migrationSnapshot = shelveSnapshot(name: "migrating")
        let staleRefreshGate = AsyncGate()
        let provider = FakeShelveProvider(
            previewText: "new preview",
            snapshotLoadOutcomes: [
                .success([baselineSnapshot]),
                .failure("stale snapshot refresh failed"),
            ],
            snapshotLoadGates: [nil, staleRefreshGate]
        )
        let viewModel = ShelveViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            shelveProvider: provider
        )
        await viewModel.load()

        let staleMigration = Task { await viewModel.migrateToOfficial(migrationSnapshot) }
        let didBlockStaleRefresh = await staleRefreshGate.waitUntilEntered()
        XCTAssertTrue(didBlockStaleRefresh)

        await viewModel.preview(baselineSnapshot)
        XCTAssertEqual(viewModel.state, .completed(.preview))

        await staleRefreshGate.open()
        await staleMigration.value
        XCTAssertEqual(viewModel.snapshots, [baselineSnapshot])
        XCTAssertEqual(viewModel.state, .completed(.preview))
    }

    @MainActor
    func testOlderMigrationProviderFailureCannotOverwriteNewerPreviewState() async {
        let snapshot = shelveSnapshot(name: "migrating")
        let migrationGate = AsyncGate()
        let provider = FakeShelveProvider(
            previewText: "new preview",
            migrationGate: migrationGate,
            migrationError: "stale migration failed"
        )
        let viewModel = ShelveViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            shelveProvider: provider
        )

        let staleMigration = Task { await viewModel.migrateToOfficial(snapshot) }
        let didBlockMigration = await migrationGate.waitUntilEntered()
        XCTAssertTrue(didBlockMigration)

        await viewModel.preview(snapshot)
        XCTAssertEqual(viewModel.state, .completed(.preview))

        await migrationGate.open()
        await staleMigration.value
        XCTAssertEqual(viewModel.state, .completed(.preview))
    }

    @MainActor
    func testOlderOfficialAvailabilityCannotOverwriteNewerUnavailableResult() async {
        let staleShelf = SvnShelf(
            name: "stale",
            latestVersion: 1,
            pathCount: 1,
            ageSummary: "old",
            message: nil
        )
        let staleAvailabilityGate = AsyncGate()
        let expectedAvailability = SvnShelvingAvailability.unavailable(
            .v3,
            reason: "new load unavailable"
        )
        let provider = FakeShelveProvider(
            officialAvailabilityOutcomes: [
                .available(.v3),
                expectedAvailability,
            ],
            officialShelves: [staleShelf],
            officialGates: [staleAvailabilityGate]
        )
        let viewModel = ShelveViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            shelveProvider: provider
        )

        let staleLoad = Task { await viewModel.load() }
        let didBlockStaleAvailability = await staleAvailabilityGate.waitUntilEntered()
        XCTAssertTrue(didBlockStaleAvailability)

        await viewModel.load()
        XCTAssertEqual(viewModel.officialAvailability, expectedAvailability)
        XCTAssertTrue(viewModel.officialShelves.isEmpty)
        XCTAssertNil(viewModel.officialError)

        await staleAvailabilityGate.open()
        await staleLoad.value
        XCTAssertEqual(viewModel.officialAvailability, expectedAvailability)
        XCTAssertTrue(viewModel.officialShelves.isEmpty)
        XCTAssertNil(viewModel.officialError)
    }

    @MainActor
    func testOlderOfficialShelfFailureCannotOverwriteNewerShelfResult() async {
        let currentShelf = SvnShelf(
            name: "current",
            latestVersion: 2,
            pathCount: 2,
            ageSummary: "new",
            message: nil
        )
        let staleShelvesGate = AsyncGate()
        let provider = FakeShelveProvider(
            officialAvailability: .available(.v3),
            officialShelvesOutcomes: [
                .failure("stale official shelves failed"),
                .success([currentShelf]),
            ],
            officialShelvesGates: [staleShelvesGate, nil]
        )
        let viewModel = ShelveViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            shelveProvider: provider
        )

        let staleLoad = Task { await viewModel.load() }
        let didBlockStaleShelves = await staleShelvesGate.waitUntilEntered()
        XCTAssertTrue(didBlockStaleShelves)

        await viewModel.load()
        XCTAssertEqual(viewModel.officialShelves, [currentShelf])
        XCTAssertNil(viewModel.officialError)

        await staleShelvesGate.open()
        await staleLoad.value
        XCTAssertEqual(viewModel.officialShelves, [currentShelf])
        XCTAssertNil(viewModel.officialError)
    }
}

private enum SnapshotLoadOutcome: Sendable {
    case success([ShelveSnapshot])
    case failure(String)
}

private enum OfficialShelvesOutcome: Sendable {
    case success([SvnShelf])
    case failure(String)
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
    private var snapshotLoadOutcomes: [SnapshotLoadOutcome]
    private var snapshotLoadGates: [AsyncGate?]
    private var shelveCalls: [ShelveCreateCall] = []
    private var safetyCalls: [ShelveCreateCall] = []
    private var restoreCalls: [ShelveRestoreCall] = []
    private var deleteCalls: [ShelveSnapshot] = []
    private let officialAvailabilityResult: SvnShelvingAvailability
    private var officialAvailabilityOutcomes: [SvnShelvingAvailability]
    private let officialShelvesResult: [SvnShelf]
    private var officialShelvesOutcomes: [OfficialShelvesOutcome]
    private var officialShelvesGates: [AsyncGate?]
    private let officialDiffText: String
    private let officialLogText: String
    private var officialGates: [AsyncGate]
    private var officialCalls: [String] = []
    private var migrationSnapshots: [ShelveSnapshot] = []
    private let migrationGate: AsyncGate?
    private let migrationError: String?

    init(
        snapshots: [ShelveSnapshot] = [],
        previewText: String = "",
        shelveResult: ShelveSnapshot? = nil,
        safetyResult: ShelveSnapshot? = nil,
        loadError: Error? = nil,
        snapshotLoadOutcomes: [SnapshotLoadOutcome] = [],
        snapshotLoadGates: [AsyncGate?] = [],
        officialAvailability: SvnShelvingAvailability = .unavailable(.v3, reason: "not configured"),
        officialAvailabilityOutcomes: [SvnShelvingAvailability] = [],
        officialShelves: [SvnShelf] = [],
        officialShelvesOutcomes: [OfficialShelvesOutcome] = [],
        officialShelvesGates: [AsyncGate?] = [],
        officialDiffText: String = "",
        officialLogText: String = "",
        officialGate: AsyncGate? = nil,
        officialGates: [AsyncGate] = [],
        migrationGate: AsyncGate? = nil,
        migrationError: String? = nil
    ) {
        self.snapshots = snapshots
        self.previewText = previewText
        self.shelveResult = shelveResult
        self.safetyResult = safetyResult
        self.loadError = loadError
        self.snapshotLoadOutcomes = snapshotLoadOutcomes
        self.snapshotLoadGates = snapshotLoadGates
        self.officialAvailabilityResult = officialAvailability
        self.officialAvailabilityOutcomes = officialAvailabilityOutcomes
        self.officialShelvesResult = officialShelves
        self.officialShelvesOutcomes = officialShelvesOutcomes
        self.officialShelvesGates = officialShelvesGates
        self.officialDiffText = officialDiffText
        self.officialLogText = officialLogText
        self.officialGates = officialGates.isEmpty ? officialGate.map { [$0] } ?? [] : officialGates
        self.migrationGate = migrationGate
        self.migrationError = migrationError
    }

    func load() async throws -> [ShelveSnapshot] {
        let gate = snapshotLoadGates.isEmpty ? nil : snapshotLoadGates.removeFirst()
        let outcome = snapshotLoadOutcomes.isEmpty ? nil : snapshotLoadOutcomes.removeFirst()
        if let gate {
            await gate.wait()
        }
        if let outcome {
            switch outcome {
            case .success(let snapshots):
                return snapshots
            case .failure(let detail):
                throw SvnError.network(detail: detail)
            }
        }
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
        let outcome = officialAvailabilityOutcomes.isEmpty
            ? officialAvailabilityResult
            : officialAvailabilityOutcomes.removeFirst()
        if !officialGates.isEmpty {
            let officialGate = officialGates.removeFirst()
            await officialGate.wait()
        }
        return outcome
    }

    func officialShelves(wc: URL) async throws -> [SvnShelf] {
        let gate = officialShelvesGates.isEmpty ? nil : officialShelvesGates.removeFirst()
        let outcome = officialShelvesOutcomes.isEmpty ? nil : officialShelvesOutcomes.removeFirst()
        if let gate {
            await gate.wait()
        }
        if let outcome {
            switch outcome {
            case .success(let shelves):
                return shelves
            case .failure(let detail):
                throw SvnError.network(detail: detail)
            }
        }
        return officialShelvesResult
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
        if let migrationGate {
            await migrationGate.wait()
        }
        if let migrationError {
            throw SvnError.network(detail: migrationError)
        }
    }

    func recordedMigrationSnapshots() -> [ShelveSnapshot] {
        migrationSnapshots
    }
}

private actor AsyncGate {
    private var isEntered = false
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }
        isEntered = true
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered(timeout: Duration = .seconds(1)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !isEntered {
            if clock.now >= deadline {
                return false
            }
            await Task.yield()
        }
        return true
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
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
