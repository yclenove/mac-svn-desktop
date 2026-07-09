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

        let summary = try await service.update(wc: wc, paths: ["src"], revision: Revision(9), setDepth: .files)
        let requestedWorkingCopies = await provider.recordedWorkingCopies()

        XCTAssertEqual(summary, UpdateSummary(updated: 1, revision: Revision(9)))
        XCTAssertEqual(requestedWorkingCopies, [wc])
        XCTAssertEqual(backend.calls.map(\.name), ["update", "update"])
        XCTAssertEqual(backend.updateCredentials, [nil, Credential(username: "u", password: "p")])
        XCTAssertEqual(backend.updateSetDepths, [.files, .files])
    }

    func testCheckoutPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
        let backend = MockSvnBackend()
        backend.checkoutErrors = [.authentication]
        let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
        let service = SvnService(backend: backend, credentialProvider: provider)
        let destination = URL(fileURLWithPath: "/tmp/wc")

        try await service.checkout(url: "file:///repo/trunk", to: destination, depth: .files, auth: nil)
        let requestedWorkingCopies = await provider.recordedWorkingCopies()

        XCTAssertEqual(requestedWorkingCopies, [destination])
        XCTAssertEqual(backend.calls.map(\.name), ["checkout", "checkout"])
        XCTAssertEqual(backend.checkoutCredentials, [nil, Credential(username: "u", password: "p")])
        XCTAssertEqual(backend.checkoutDepths, [.files, .files])
    }

    func testCopyRejectsEmptyMessageBeforeBackendCall() async throws {
        let backend = MockSvnBackend()
        let service = SvnService(backend: backend)

        do {
            _ = try await service.copy(
                source: "file:///repo/trunk",
                destination: "file:///repo/branches/dev",
                message: "  ",
                auth: nil
            )
            XCTFail("Expected emptyCommitMessage")
        } catch let error as SvnServiceError {
            XCTAssertEqual(error, .emptyCommitMessage)
        } catch {
            XCTFail("Expected SvnServiceError, got \(error)")
        }

        XCTAssertTrue(backend.calls.isEmpty)
    }

    func testCopyPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
        let backend = MockSvnBackend()
        backend.copyErrors = [.authentication]
        backend.copyResult = Revision(12)
        let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
        let service = SvnService(backend: backend, credentialProvider: provider)

        let revision = try await service.copy(
            source: "file:///repo/trunk",
            destination: "file:///repo/branches/dev",
            message: "create dev",
            auth: nil
        )
        let requestedScopes = await provider.recordedWorkingCopies()

        XCTAssertEqual(revision, Revision(12))
        XCTAssertEqual(requestedScopes, [URL(string: "file:///repo/branches/dev")!])
        XCTAssertEqual(backend.calls.map(\.name), ["copy", "copy"])
        XCTAssertEqual(backend.copyCredentials, [nil, Credential(username: "u", password: "p")])
    }

    func testSwitchBlocksLocalChangesBeforeBackendSwitchByDefault() async {
        let backend = MockSvnBackend()
        backend.statusResult = [
            FileStatus(path: "README.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false),
            FileStatus(path: "new.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false)
        ]
        let service = SvnService(backend: backend)

        do {
            _ = try await service.switchTo(
                wc: URL(fileURLWithPath: "/tmp/wc"),
                url: "file:///repo/branches/feature-one",
                auth: nil
            )
            XCTFail("Expected localChangesPreventSwitch")
        } catch let error as SvnServiceError {
            XCTAssertEqual(error, .localChangesPreventSwitch(paths: ["README.txt", "new.txt"]))
        } catch {
            XCTFail("Expected SvnServiceError, got \(error)")
        }

        XCTAssertEqual(backend.calls.map(\.name), ["status"])
    }

    func testSwitchAllowsLocalChangesWhenConfirmed() async throws {
        let backend = MockSvnBackend()
        backend.statusResult = [
            FileStatus(path: "README.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false)
        ]
        backend.switchResult = UpdateSummary(updated: 1, revision: Revision(9))
        let service = SvnService(backend: backend)

        let summary = try await service.switchTo(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            url: "file:///repo/branches/feature-one",
            auth: nil,
            allowLocalChanges: true
        )

        XCTAssertEqual(summary, UpdateSummary(updated: 1, revision: Revision(9)))
        XCTAssertEqual(backend.calls.map(\.name), ["status", "switch"])
    }

    func testSwitchPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
        let backend = MockSvnBackend()
        backend.switchErrors = [.authentication]
        backend.switchResult = UpdateSummary(revision: Revision(10))
        let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
        let service = SvnService(backend: backend, credentialProvider: provider)

        let summary = try await service.switchTo(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            url: "file:///repo/branches/feature-one",
            auth: nil
        )
        let requestedScopes = await provider.recordedWorkingCopies()

        XCTAssertEqual(summary, UpdateSummary(revision: Revision(10)))
        XCTAssertEqual(requestedScopes, [URL(string: "file:///repo/branches/feature-one")!])
        XCTAssertEqual(backend.calls.map(\.name), ["status", "switch", "switch"])
        XCTAssertEqual(backend.switchCredentials, [nil, Credential(username: "u", password: "p")])
    }

    func testListPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
        let backend = MockSvnBackend()
        backend.listErrors = [.authentication]
        backend.listResult = [
            RemoteEntry(
                name: "trunk",
                path: "trunk",
                kind: .directory,
                size: nil,
                revision: Revision(1),
                author: "a",
                date: nil
            )
        ]
        let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
        let service = SvnService(backend: backend, credentialProvider: provider)

        let entries = try await service.list(url: "file:///repo", depth: .immediates, auth: nil)
        let requestedScopes = await provider.recordedWorkingCopies()

        XCTAssertEqual(entries.map(\.name), ["trunk"])
        XCTAssertEqual(requestedScopes, [URL(string: "file:///repo")!])
        XCTAssertEqual(backend.calls.map(\.name), ["list", "list"])
        XCTAssertEqual(backend.listCredentials, [nil, Credential(username: "u", password: "p")])
        XCTAssertEqual(backend.listDepths, [.immediates, .immediates])
    }

    func testCatPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
        let backend = MockSvnBackend()
        backend.catErrors = [.authentication]
        backend.catResult = Data("hello".utf8)
        let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
        let service = SvnService(backend: backend, credentialProvider: provider)

        let data = try await service.cat(url: "file:///repo/trunk/README.txt", revision: nil, sizeLimit: 5, auth: nil)
        let requestedScopes = await provider.recordedWorkingCopies()

        XCTAssertEqual(String(data: data, encoding: .utf8), "hello")
        XCTAssertEqual(requestedScopes, [URL(string: "file:///repo/trunk/README.txt")!])
        XCTAssertEqual(backend.calls.map(\.name), ["cat", "cat"])
        XCTAssertEqual(backend.catCredentials, [nil, Credential(username: "u", password: "p")])
        XCTAssertEqual(backend.catSizeLimits, [5, 5])
    }

    func testRemoteLogPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
        let backend = MockSvnBackend()
        backend.remoteLogErrors = [.authentication]
        backend.remoteLogResult = [
            LogEntry(revision: Revision(7), author: "a", date: nil, message: "m", changedPaths: [])
        ]
        let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
        let service = SvnService(backend: backend, credentialProvider: provider)

        let entries = try await service.remoteLog(
            url: "file:///repo/trunk",
            from: Revision(7),
            batch: 10,
            verbose: true,
            auth: nil
        )
        let requestedScopes = await provider.recordedWorkingCopies()

        XCTAssertEqual(entries.map(\.revision), [Revision(7)])
        XCTAssertEqual(requestedScopes, [URL(string: "file:///repo/trunk")!])
        XCTAssertEqual(backend.calls.map(\.name), ["remoteLog", "remoteLog"])
        XCTAssertEqual(backend.remoteLogCredentials, [nil, Credential(username: "u", password: "p")])
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
    private var recordedUpdateSetDepths: [SvnDepth?] = []
    private var recordedCommitCredentials: [Credential?] = []
    private var recordedCheckoutCredentials: [Credential?] = []
    private var recordedCheckoutDepths: [SvnDepth] = []
    private var recordedListCredentials: [Credential?] = []
    private var recordedListDepths: [SvnDepth] = []
    private var recordedCatCredentials: [Credential?] = []
    private var recordedCatSizeLimits: [Int] = []
    private var recordedRemoteLogCredentials: [Credential?] = []
    private var recordedCopyCredentials: [Credential?] = []
    private var recordedSwitchCredentials: [Credential?] = []

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

    var updateSetDepths: [SvnDepth?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedUpdateSetDepths
    }

    var commitCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedCommitCredentials
    }

    var checkoutCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedCheckoutCredentials
    }

    var checkoutDepths: [SvnDepth] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedCheckoutDepths
    }

    var listCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedListCredentials
    }

    var listDepths: [SvnDepth] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedListDepths
    }

    var catCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedCatCredentials
    }

    var catSizeLimits: [Int] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedCatSizeLimits
    }

    var remoteLogCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedRemoteLogCredentials
    }

    var copyCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedCopyCredentials
    }

    var switchCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedSwitchCredentials
    }

    var statusResult: [FileStatus] = []
    var diffResult = ""
    var logResult: [LogEntry] = []
    var infoResult = SvnInfo(path: ".", url: "file:///repo/trunk", repositoryRoot: "file:///repo", revision: Revision(1), kind: "dir")
    var listResult: [RemoteEntry] = []
    var catResult = Data()
    var remoteLogResult: [LogEntry] = []
    var copyResult = Revision(1)
    var switchResult = UpdateSummary()
    var commitResult = Revision(1)
    var commitErrors: [SvnError] = []
    var updateResult = UpdateSummary()
    var updateErrors: [SvnError] = []
    var checkoutErrors: [SvnError] = []
    var listErrors: [SvnError] = []
    var catErrors: [SvnError] = []
    var remoteLogErrors: [SvnError] = []
    var copyErrors: [SvnError] = []
    var switchErrors: [SvnError] = []
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

    func update(
        wc: URL,
        paths: [String],
        revision: Revision?,
        setDepth: SvnDepth?,
        auth: Credential?
    ) async throws -> UpdateSummary {
        let error = recordUpdate(setDepth: setDepth, auth: auth)
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

    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry] {
        let error = recordList(depth: depth, auth: auth)
        if let error {
            throw error
        }
        return listResult
    }

    func cat(url: String, revision: Revision?, sizeLimit: Int, auth: Credential?) async throws -> Data {
        let error = recordCat(sizeLimit: sizeLimit, auth: auth)
        if let error {
            throw error
        }
        return catResult
    }

    func remoteLog(url: String, from: Revision, batch: Int, verbose: Bool, auth: Credential?) async throws -> [LogEntry] {
        let error = recordRemoteLog(auth: auth)
        if let error {
            throw error
        }
        return remoteLogResult
    }

    func checkout(url: String, to destination: URL, depth: SvnDepth, auth: Credential?) async throws {
        let error = recordCheckout(depth: depth, auth: auth)
        if let error {
            throw error
        }
    }

    func copy(source: String, destination: String, message: String, auth: Credential?) async throws -> Revision {
        let error = recordCopy(auth: auth)
        if let error {
            throw error
        }
        return copyResult
    }

    func switchTo(wc: URL, url: String, auth: Credential?) async throws -> UpdateSummary {
        let error = recordSwitch(auth: auth)
        if let error {
            throw error
        }
        return switchResult
    }

    func info(wc: URL, target: String) async throws -> SvnInfo {
        record("info")
        return infoResult
    }

    private func recordUpdate(setDepth: SvnDepth?, auth: Credential?) -> SvnError? {
        callsLock.lock()
        recordedCalls.append(Call(name: "update"))
        recordedUpdateSetDepths.append(setDepth)
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

    private func recordCheckout(depth: SvnDepth, auth: Credential?) -> SvnError? {
        callsLock.lock()
        recordedCalls.append(Call(name: "checkout"))
        recordedCheckoutDepths.append(depth)
        recordedCheckoutCredentials.append(auth)
        let error = checkoutErrors.isEmpty ? nil : checkoutErrors.removeFirst()
        callsLock.unlock()
        return error
    }

    private func recordList(depth: SvnDepth, auth: Credential?) -> SvnError? {
        callsLock.lock()
        recordedCalls.append(Call(name: "list"))
        recordedListDepths.append(depth)
        recordedListCredentials.append(auth)
        let error = listErrors.isEmpty ? nil : listErrors.removeFirst()
        callsLock.unlock()
        return error
    }

    private func recordCat(sizeLimit: Int, auth: Credential?) -> SvnError? {
        callsLock.lock()
        recordedCalls.append(Call(name: "cat"))
        recordedCatSizeLimits.append(sizeLimit)
        recordedCatCredentials.append(auth)
        let error = catErrors.isEmpty ? nil : catErrors.removeFirst()
        callsLock.unlock()
        return error
    }

    private func recordRemoteLog(auth: Credential?) -> SvnError? {
        callsLock.lock()
        recordedCalls.append(Call(name: "remoteLog"))
        recordedRemoteLogCredentials.append(auth)
        let error = remoteLogErrors.isEmpty ? nil : remoteLogErrors.removeFirst()
        callsLock.unlock()
        return error
    }

    private func recordCopy(auth: Credential?) -> SvnError? {
        callsLock.lock()
        recordedCalls.append(Call(name: "copy"))
        recordedCopyCredentials.append(auth)
        let error = copyErrors.isEmpty ? nil : copyErrors.removeFirst()
        callsLock.unlock()
        return error
    }

    private func recordSwitch(auth: Credential?) -> SvnError? {
        callsLock.lock()
        recordedCalls.append(Call(name: "switch"))
        recordedSwitchCredentials.append(auth)
        let error = switchErrors.isEmpty ? nil : switchErrors.removeFirst()
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
