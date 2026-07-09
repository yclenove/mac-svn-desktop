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

        XCTAssertEqual(viewModel.state, .confirmationRequired(.lock, ["README.txt"]))
        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [])
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
