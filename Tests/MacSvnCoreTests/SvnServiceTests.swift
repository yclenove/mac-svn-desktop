import Foundation
import XCTest
@testable import MacSvnCore

final class SvnServiceTests: XCTestCase {
    func testQueryMethodsForwardToBackend() async throws {
        let backend = MockSvnBackend()
        backend.statusResult = [
            FileStatus(path: "a.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false)
        ]
        backend.diffResult = "@@ diff"
        backend.logResult = [
            LogEntry(revision: Revision(3), author: "a", date: nil, message: "m", changedPaths: [])
        ]
        backend.infoResult = SvnInfo(path: ".", url: "file:///repo/trunk", repositoryRoot: "file:///repo", revision: Revision(3), kind: "dir")
        let service = SvnService(backend: backend)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        let statuses = try await service.status(wc: wc)
        let diff = try await service.diff(wc: wc, target: "a.txt", r1: nil, r2: nil)
        let log = try await service.log(wc: wc, target: "trunk", from: Revision(9), batch: 10, verbose: true)
        let info = try await service.info(wc: wc, target: ".")

        XCTAssertEqual(statuses, backend.statusResult)
        XCTAssertEqual(diff, "@@ diff")
        XCTAssertEqual(log, backend.logResult)
        XCTAssertEqual(info, backend.infoResult)
        XCTAssertEqual(backend.calls.map(\.name), ["status", "diff", "log", "info"])
    }

    func testCommitRejectsEmptyMessage() async {
        let backend = MockSvnBackend()
        let service = SvnService(backend: backend)

        do {
            _ = try await service.commit(wc: URL(fileURLWithPath: "/tmp/wc"), paths: ["a.txt"], message: "  ", auth: nil)
            XCTFail("Expected empty message error")
        } catch let error as SvnServiceError {
            XCTAssertEqual(error, .emptyCommitMessage)
        } catch {
            XCTFail("Expected SvnServiceError, got \(error)")
        }

        XCTAssertTrue(backend.calls.isEmpty)
    }

    func testCommitRejectsConflictedSelectedFilesBeforeBackendCommit() async {
        let backend = MockSvnBackend()
        backend.statusResult = [
            FileStatus(path: "ok.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false),
            FileStatus(path: "conflict.txt", itemStatus: .conflicted, revision: Revision(2), isTreeConflict: false),
            FileStatus(path: "tree.txt", itemStatus: .modified, revision: Revision(3), isTreeConflict: true)
        ]
        let service = SvnService(backend: backend)

        do {
            _ = try await service.commit(
                wc: URL(fileURLWithPath: "/tmp/wc"),
                paths: ["conflict.txt", "tree.txt"],
                message: "fix",
                auth: nil
            )
            XCTFail("Expected conflict error")
        } catch let error as SvnError {
            XCTAssertEqual(error, .conflict(paths: ["conflict.txt", "tree.txt"]))
        } catch {
            XCTFail("Expected SvnError, got \(error)")
        }

        XCTAssertEqual(backend.calls.map(\.name), ["status"])
    }

    func testCommitCallsBackendWhenSelectedFilesAreClean() async throws {
        let backend = MockSvnBackend()
        backend.statusResult = [
            FileStatus(path: "a.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false)
        ]
        backend.commitResult = Revision(42)
        let service = SvnService(backend: backend)

        let revision = try await service.commit(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            paths: ["a.txt"],
            message: "fix",
            auth: Credential(username: "u", password: "p")
        )

        XCTAssertEqual(revision, Revision(42))
        XCTAssertEqual(backend.calls.map(\.name), ["status", "commit"])
    }

    func testUpdatePromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
        let backend = MockSvnBackend()
        backend.updateErrors = [.authentication]
        backend.updateResult = UpdateSummary(updated: 1, revision: Revision(9))
        let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
        let service = SvnService(backend: backend, credentialProvider: provider)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        let summary = try await service.update(wc: wc)
        let requestedWorkingCopies = await provider.recordedWorkingCopies()

        XCTAssertEqual(summary, UpdateSummary(updated: 1, revision: Revision(9)))
        XCTAssertEqual(requestedWorkingCopies, [wc])
        XCTAssertEqual(backend.calls.map(\.name), ["update", "update"])
        XCTAssertEqual(backend.updateCredentials, [nil, Credential(username: "u", password: "p")])
    }

    func testCommitPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
        let backend = MockSvnBackend()
        backend.statusResult = [
            FileStatus(path: "a.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false)
        ]
        backend.commitErrors = [.authentication]
        backend.commitResult = Revision(42)
        let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
        let service = SvnService(backend: backend, credentialProvider: provider)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        let revision = try await service.commit(
            wc: wc,
            paths: ["a.txt"],
            message: "fix",
            auth: nil
        )
        let requestedWorkingCopies = await provider.recordedWorkingCopies()

        XCTAssertEqual(revision, Revision(42))
        XCTAssertEqual(requestedWorkingCopies, [wc])
        XCTAssertEqual(backend.calls.map(\.name), ["status", "commit", "commit"])
        XCTAssertEqual(backend.commitCredentials, [nil, Credential(username: "u", password: "p")])
    }

    func testCommitOnlyPromptsOnceWhenAuthenticationRetryFails() async {
        let backend = MockSvnBackend()
        backend.statusResult = [
            FileStatus(path: "a.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false)
        ]
        backend.commitErrors = [.authentication, .authentication]
        let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
        let service = SvnService(backend: backend, credentialProvider: provider)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        do {
            _ = try await service.commit(wc: wc, paths: ["a.txt"], message: "fix", auth: nil)
            XCTFail("Expected authentication error")
        } catch let error as SvnError {
            XCTAssertEqual(error, .authentication)
        } catch {
            XCTFail("Expected SvnError, got \(error)")
        }
        let requestedWorkingCopies = await provider.recordedWorkingCopies()

        XCTAssertEqual(requestedWorkingCopies, [wc])
        XCTAssertEqual(backend.calls.map(\.name), ["status", "commit", "commit"])
        XCTAssertEqual(backend.commitCredentials, [nil, Credential(username: "u", password: "p")])
    }

    func testConcurrentWritesOnSameWorkingCopyThrowBusy() async throws {
        let backend = MockSvnBackend()
        let service = SvnService(backend: backend)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        let firstUpdateStarted = XCTestExpectation(description: "first update started")
        let releaseFirstUpdate = AsyncGate()
        backend.onUpdate = { _ in
            firstUpdateStarted.fulfill()
            await releaseFirstUpdate.wait()
        }

        let firstTask = Task {
            try await service.update(wc: wc, paths: [], revision: nil)
        }

        await fulfillment(of: [firstUpdateStarted], timeout: 1)

        do {
            _ = try await service.update(wc: wc, paths: [], revision: nil)
            XCTFail("Expected wc busy")
        } catch let error as SvnServiceError {
            XCTAssertEqual(error, .wcBusy(operation: "update"))
        } catch {
            XCTFail("Expected SvnServiceError, got \(error)")
        }

        await releaseFirstUpdate.open()
        _ = try await firstTask.value
    }

    func testConcurrentWritesOnDifferentWorkingCopiesCanRun() async throws {
        let backend = MockSvnBackend()
        let service = SvnService(backend: backend)
        let firstWC = URL(fileURLWithPath: "/tmp/wc-a")
        let secondWC = URL(fileURLWithPath: "/tmp/wc-b")

        let firstUpdateStarted = XCTestExpectation(description: "first update started")
        let releaseFirstUpdate = AsyncGate()
        backend.onUpdate = { wc in
            guard wc == firstWC else {
                return
            }

            firstUpdateStarted.fulfill()
            await releaseFirstUpdate.wait()
        }

        let firstTask = Task {
            try await service.update(wc: firstWC, paths: [], revision: nil)
        }

        await fulfillment(of: [firstUpdateStarted], timeout: 1)

        _ = try await service.update(wc: secondWC, paths: [], revision: nil)

        await releaseFirstUpdate.open()
        _ = try await firstTask.value
        XCTAssertEqual(backend.calls.map(\.name), ["update", "update"])
    }
}

private final class MockSvnBackend: SvnBackend, @unchecked Sendable {
    struct Call: Equatable {
        let name: String
    }

    private let callsLock = NSLock()
    private var recordedCalls: [Call] = []
    private var recordedUpdateCredentials: [Credential?] = []
    private var recordedCommitCredentials: [Credential?] = []

    var calls: [Call] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedCalls
    }

    var updateCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedUpdateCredentials
    }

    var commitCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedCommitCredentials
    }

    var statusResult: [FileStatus] = []
    var diffResult = ""
    var logResult: [LogEntry] = []
    var infoResult = SvnInfo(path: ".", url: "file:///repo/trunk", repositoryRoot: "file:///repo", revision: Revision(1), kind: "dir")
    var commitResult = Revision(1)
    var commitErrors: [SvnError] = []
    var updateResult = UpdateSummary()
    var updateErrors: [SvnError] = []
    var onUpdate: ((URL) async -> Void)?

    private func record(_ name: String) {
        callsLock.lock()
        recordedCalls.append(Call(name: name))
        callsLock.unlock()
    }

    func version() async throws -> SvnVersion {
        record("version")
        return SvnVersion(major: 1, minor: 14, patch: 5)
    }

    func status(wc: URL) async throws -> [FileStatus] {
        record("status")
        return statusResult
    }

    func update(wc: URL, paths: [String], revision: Revision?, auth: Credential?) async throws -> UpdateSummary {
        let error = recordUpdate(auth: auth)
        await onUpdate?(wc)
        if let error {
            throw error
        }
        return updateResult
    }

    func commit(wc: URL, paths: [String], message: String, auth: Credential?) async throws -> Revision {
        let error = recordCommit(auth: auth)
        if let error {
            throw error
        }
        return commitResult
    }

    func add(wc: URL, paths: [String]) async throws {
        record("add")
    }

    func delete(wc: URL, paths: [String]) async throws {
        record("delete")
    }

    func revert(wc: URL, paths: [String], recursive: Bool) async throws {
        record("revert")
    }

    func cleanup(wc: URL) async throws {
        record("cleanup")
    }

    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        record("diff")
        return diffResult
    }

    func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry] {
        record("log")
        return logResult
    }

    func checkout(url: String, to destination: URL) async throws {
        record("checkout")
    }

    func info(wc: URL, target: String) async throws -> SvnInfo {
        record("info")
        return infoResult
    }

    private func recordUpdate(auth: Credential?) -> SvnError? {
        callsLock.lock()
        recordedCalls.append(Call(name: "update"))
        recordedUpdateCredentials.append(auth)
        let error = updateErrors.isEmpty ? nil : updateErrors.removeFirst()
        callsLock.unlock()
        return error
    }

    private func recordCommit(auth: Credential?) -> SvnError? {
        callsLock.lock()
        recordedCalls.append(Call(name: "commit"))
        recordedCommitCredentials.append(auth)
        let error = commitErrors.isEmpty ? nil : commitErrors.removeFirst()
        callsLock.unlock()
        return error
    }
}

private actor FakeCredentialProvider: CredentialProviding {
    private var requests: [URL] = []
    private let credential: Credential?

    func recordedWorkingCopies() -> [URL] {
        return requests
    }

    init(credential: Credential?) {
        self.credential = credential
    }

    func credential(for wc: URL) async throws -> Credential? {
        requests.append(wc)
        return credential
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen {
            return
        }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}
