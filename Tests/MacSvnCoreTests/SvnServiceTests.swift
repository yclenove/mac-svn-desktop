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
        let service = SvnService(backend: backend)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        let statuses = try await service.status(wc: wc)
        let diff = try await service.diff(wc: wc, target: "a.txt", r1: nil, r2: nil)
        let log = try await service.log(wc: wc, target: "trunk", from: Revision(9), batch: 10, verbose: true)

        XCTAssertEqual(statuses, backend.statusResult)
        XCTAssertEqual(diff, "@@ diff")
        XCTAssertEqual(log, backend.logResult)
        XCTAssertEqual(backend.calls.map(\.name), ["status", "diff", "log"])
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

    var calls: [Call] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedCalls
    }

    var statusResult: [FileStatus] = []
    var diffResult = ""
    var logResult: [LogEntry] = []
    var commitResult = Revision(1)
    var updateResult = UpdateSummary()
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

    func update(wc: URL, paths: [String], revision: Revision?) async throws -> UpdateSummary {
        record("update")
        await onUpdate?(wc)
        return updateResult
    }

    func commit(wc: URL, paths: [String], message: String, auth: Credential?) async throws -> Revision {
        record("commit")
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
