import Foundation
import XCTest
@testable import MacSvnCore

final class LockViewModelTests: XCTestCase {
    @MainActor
    func testLoadLockUnlockAndRefreshesLocks() async {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakeLockProvider(results: [
            .success([]),
            .success([
                SvnLock(
                    target: "README.txt",
                    token: "t",
                    owner: "u",
                    comment: "note",
                    created: nil,
                    isOwnedByWorkingCopy: true,
                    isRepositoryLocked: true
                )
            ]),
            .success([])
        ])
        let viewModel = LockViewModel(workingCopy: wc, provider: provider)

        await viewModel.load(targets: ["README.txt"])
        await viewModel.lock(paths: ["README.txt"], message: "note", force: false)
        await viewModel.unlock(paths: ["README.txt"], force: false)

        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.locks, [])
        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [
            LockProviderCall(operation: "locks", wc: wc, paths: ["README.txt"], message: nil, force: false),
            LockProviderCall(operation: "lock", wc: wc, paths: ["README.txt"], message: "note", force: false),
            LockProviderCall(operation: "locks", wc: wc, paths: ["README.txt"], message: nil, force: false),
            LockProviderCall(operation: "unlock", wc: wc, paths: ["README.txt"], message: nil, force: false),
            LockProviderCall(operation: "locks", wc: wc, paths: ["README.txt"], message: nil, force: false)
        ])
    }

    @MainActor
    func testForceLockRequiresConfirmationBeforeProviderCall() async {
        let provider = FakeLockProvider(results: [.success([])])
        let viewModel = LockViewModel(workingCopy: URL(fileURLWithPath: "/tmp/wc"), provider: provider)

        await viewModel.lock(paths: ["README.txt"], message: nil, force: true, confirmed: false)

        XCTAssertEqual(viewModel.state, .confirmationRequired(.stealLock, ["README.txt"]))
        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [])
    }

    @MainActor
    func testBreakLockRequiresConfirmationThenUnlocksWithForce() async {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakeLockProvider(results: [
            .success([
                SvnLock(
                    target: "other.txt",
                    token: "t",
                    owner: "alice",
                    comment: nil,
                    created: nil,
                    isOwnedByWorkingCopy: false,
                    isRepositoryLocked: true
                )
            ]),
            .success([])
        ])
        let viewModel = LockViewModel(workingCopy: wc, provider: provider)
        await viewModel.load(targets: ["other.txt"])

        await viewModel.breakLock(paths: ["other.txt"], confirmed: false)
        XCTAssertEqual(viewModel.state, .confirmationRequired(.breakLock, ["other.txt"]))

        await viewModel.confirmPending()
        let calls = await provider.recordedCalls()
        XCTAssertTrue(calls.contains(where: { $0.operation == "unlock" && $0.force == true }))
        XCTAssertEqual(viewModel.state, .loaded)
    }

    @MainActor
    func testRejectsEmptyPathsBeforeProviderCall() async {
        let provider = FakeLockProvider(results: [.success([])])
        let viewModel = LockViewModel(workingCopy: URL(fileURLWithPath: "/tmp/wc"), provider: provider)

        await viewModel.unlock(paths: [], force: false)

        XCTAssertEqual(viewModel.state, .error("emptyLockPaths"))
        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [])
    }

    @MainActor
    func testLockBlocksProjectMinimumMessageLengthBeforeProviderCall() async {
        let provider = FakeLockProvider(results: [.success([])])
        let viewModel = LockViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            provider: provider,
            projectProperties: ProjectPropertyPolicy(properties: [
                SvnProperty(target: ".", name: "tsvn:lockmsgminsize", value: "8")
            ])
        )

        await viewModel.lock(paths: ["README.txt"], message: "short", force: false)
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .error("lockMessageTooShort:8"))
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor
    func testLockReloadsProjectPropertiesForCurrentSingleDirectorySelection() async {
        let provider = FakeLockProvider(results: [.success([])])
        let viewModel = LockViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            provider: provider,
            projectPropertyLoader: { paths in
                ProjectPropertyPolicy(properties: paths == ["Features/A/file.swift"]
                    ? [SvnProperty(target: "Features/A", name: "tsvn:lockmsgminsize", value: "12")]
                    : [])
            }
        )

        await viewModel.lock(paths: ["Features/A/file.swift"], message: "short", force: false)
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.projectProperties.lock.minimumMessageLength, 12)
        XCTAssertEqual(viewModel.state, .error("lockMessageTooShort:12"))
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor
    func testLockBlocksWhenAnySelectedDirectoryHasStricterProjectConstraint() async {
        let provider = FakeLockProvider(results: [.success([])])
        let policyA = ProjectPropertyPolicy(properties: [
            SvnProperty(target: "Features/A", name: "tsvn:lockmsgminsize", value: "12")
        ])
        let policyB = ProjectPropertyPolicy(properties: [
            SvnProperty(target: "Features/B", name: "tsvn:lockmsgminsize", value: "4")
        ])
        let viewModel = LockViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            provider: provider,
            projectPropertyLoader: { _ in ProjectPropertyPolicy.combining([policyA, policyB]) }
        )

        await viewModel.lock(
            paths: ["Features/A/file.swift", "Features/B/file.swift"],
            message: "short",
            force: false
        )
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.projectProperties.lock.minimumMessageLength, 12)
        XCTAssertEqual(viewModel.state, .error("lockMessageTooShort:12"))
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor
    func testLockBlocksWhenProjectPropertyLoadingFails() async {
        let provider = FakeLockProvider(results: [.success([])])
        let viewModel = LockViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            provider: provider,
            projectPropertyLoader: { _ in throw ProjectPropertyLoaderLockTestError.unavailable }
        )

        await viewModel.lock(paths: ["README.txt"], message: "valid message", force: false)
        let calls = await provider.recordedCalls()

        XCTAssertEqual(viewModel.state, .error("projectPropertiesLoadFailed"))
        XCTAssertTrue(calls.isEmpty)
    }

    @MainActor
    func testLockRejectsReentryWhileLoadingProjectProperties() async throws {
        let provider = FakeLockProvider(results: [.success([]), .success([])])
        let viewModel = LockViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            provider: provider,
            projectPropertyLoader: { _ in
                try? await Task.sleep(nanoseconds: 50_000_000)
                return ProjectPropertyPolicy(properties: [])
            }
        )

        let firstLock = Task { @MainActor in
            await viewModel.lock(paths: ["README.txt"], message: "note", force: false)
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        await viewModel.lock(paths: ["README.txt"], message: "note", force: false)
        await firstLock.value

        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls.filter { $0.operation == "lock" }.count, 1)
    }

    @MainActor
    func testForceLockConfirmationRetainsOriginalMessageForProjectValidation() async {
        let provider = FakeLockProvider(results: [.success([])])
        let viewModel = LockViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            provider: provider,
            projectProperties: ProjectPropertyPolicy(properties: [
                SvnProperty(target: ".", name: "tsvn:lockmsgminsize", value: "8")
            ])
        )

        await viewModel.lock(paths: ["README.txt"], message: "lock note", force: true, confirmed: false)
        await viewModel.confirmPending()
        let calls = await provider.recordedCalls()

        XCTAssertEqual(
            calls.filter { $0.operation == "lock" }.map(\.message),
            ["lock note"]
        )
    }

    @MainActor
    func testFailedBackgroundPropertyRefreshDoesNotInterruptLockInProgress() async throws {
        let provider = FakeLockProvider(results: [.success([])])
        let viewModel = LockViewModel(
            workingCopy: URL(fileURLWithPath: "/tmp/wc"),
            provider: provider,
            projectPropertyLoader: { paths in
                if paths == ["refresh.txt"] {
                    throw ProjectPropertyLoaderLockTestError.unavailable
                }
                try await Task.sleep(nanoseconds: 80_000_000)
                return ProjectPropertyPolicy(properties: [])
            }
        )

        let lockTask = Task { @MainActor in
            await viewModel.lock(paths: ["README.txt"], message: nil, force: false)
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        await viewModel.refreshProjectProperties(for: ["refresh.txt"])

        XCTAssertEqual(viewModel.state, .locking)
        XCTAssertEqual(viewModel.projectPropertyLoadError, "projectPropertiesLoadFailed")

        await lockTask.value
        XCTAssertEqual(viewModel.state, .loaded)
    }
}

private enum ProjectPropertyLoaderLockTestError: Error {
    case unavailable
}

private struct LockProviderCall: Equatable {
    let operation: String
    let wc: URL
    let paths: [String]
    let message: String?
    let force: Bool
}

private actor FakeLockProvider: LockProviding {
    private var results: [Result<[SvnLock], Error>]
    private var calls: [LockProviderCall] = []

    init(results: [Result<[SvnLock], Error>]) {
        self.results = results
    }

    func recordedCalls() -> [LockProviderCall] {
        calls
    }

    func locks(wc: URL, targets: [String]) async throws -> [SvnLock] {
        calls.append(LockProviderCall(operation: "locks", wc: wc, paths: targets, message: nil, force: false))
        return try results.removeFirst().get()
    }

    func lock(wc: URL, paths: [String], message: String?, force: Bool) async throws {
        calls.append(LockProviderCall(operation: "lock", wc: wc, paths: paths, message: message, force: force))
    }

    func unlock(wc: URL, paths: [String], force: Bool) async throws {
        calls.append(LockProviderCall(operation: "unlock", wc: wc, paths: paths, message: nil, force: force))
    }
}
