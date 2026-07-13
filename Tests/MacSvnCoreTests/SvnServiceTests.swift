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

    func testBlameForwardsToBackend() async throws {
        let backend = MockSvnBackend()
        backend.blameResult = [
            BlameLine(lineNumber: 1, revision: Revision(7), author: "yangchao", date: nil)
        ]
        let service = SvnService(backend: backend)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        let lines = try await service.blame(wc: wc, target: "README.txt")

        XCTAssertEqual(lines, backend.blameResult)
        XCTAssertEqual(backend.calls.map(\.name), ["blame"])
    }

    func testPropertyMethodsForwardToBackendAndWritesUseLocks() async throws {
        let backend = MockSvnBackend()
        backend.propertiesResult = [
            SvnProperty(target: "README.txt", name: "svn:eol-style", value: "native")
        ]
        backend.propertyValueResult = SvnProperty(target: "README.txt", name: "svn:eol-style", value: "native")
        let service = SvnService(backend: backend)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        let properties = try await service.properties(wc: wc, target: "README.txt")
        let value = try await service.propertyValue(wc: wc, target: "README.txt", name: "svn:eol-style")
        try await service.setProperty(wc: wc, target: "README.txt", name: "custom:reviewer", value: "杨超")
        try await service.deleteProperty(wc: wc, target: "README.txt", name: "custom:reviewer")

        XCTAssertEqual(properties, backend.propertiesResult)
        XCTAssertEqual(value, backend.propertyValueResult)
        XCTAssertEqual(backend.calls.map(\.name), ["properties", "propertyValue", "setProperty", "deleteProperty"])
    }

    func testLockMethodsForwardToBackendAndWritesUseLocks() async throws {
        let backend = MockSvnBackend()
        backend.locksResult = [
            SvnLock(
                target: "README.txt",
                token: "t",
                owner: "u",
                comment: nil,
                created: nil,
                isOwnedByWorkingCopy: true,
                isRepositoryLocked: true
            )
        ]
        let service = SvnService(backend: backend)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        let locks = try await service.locks(wc: wc, targets: ["README.txt"])
        try await service.lock(wc: wc, paths: ["README.txt"], message: "note", force: true)
        try await service.unlock(wc: wc, paths: ["README.txt"], force: true)

        XCTAssertEqual(locks, backend.locksResult)
        XCTAssertEqual(backend.calls.map(\.name), ["locks", "lock", "unlock"])
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

    func testMultiPathUpdatePinsRepositoryHeadBeforeUpdating() async throws {
        let backend = MockSvnBackend()
        backend.headRevisionResult = Revision(42)
        backend.updateResult = UpdateSummary(updated: 2, revision: Revision(42))
        let service = SvnService(backend: backend)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        let summary = try await service.update(wc: wc, paths: ["a.txt", "b.txt"], revision: nil)

        XCTAssertEqual(summary.revision, Revision(42))
        XCTAssertEqual(backend.calls.map(\.name), ["repositoryHeadRevision", "update"])
        XCTAssertEqual(backend.updateRevisions, [Revision(42)])
    }

    func testSinglePathUpdateDoesNotPinHead() async throws {
        let backend = MockSvnBackend()
        backend.updateResult = UpdateSummary(updated: 1, revision: Revision(7))
        let service = SvnService(backend: backend)

        _ = try await service.update(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            paths: ["only.txt"],
            revision: nil
        )

        XCTAssertEqual(backend.calls.map(\.name), ["update"])
        XCTAssertEqual(backend.updateRevisions, [nil])
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

    func testExportPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
        let backend = MockSvnBackend()
        backend.exportErrors = [.authentication]
        let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
        let service = SvnService(backend: backend, credentialProvider: provider)
        let destination = URL(fileURLWithPath: "/tmp/export")

        try await service.export(
            url: "file:///repo/trunk",
            to: destination,
            revision: Revision(7),
            auth: nil
        )
        let requestedScopes = await provider.recordedWorkingCopies()

        XCTAssertEqual(requestedScopes, [URL(string: "file:///repo/trunk")!])
        XCTAssertEqual(backend.calls.map(\.name), ["export", "export"])
        XCTAssertEqual(backend.exportCredentials, [nil, Credential(username: "u", password: "p")])
        XCTAssertEqual(backend.exportRevisions, [Revision(7), Revision(7)])
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

    func testRemoteRepositoryWritesRejectEmptyMessagesBeforeBackendCall() async throws {
        let backend = MockSvnBackend()
        let service = SvnService(backend: backend)

        do {
            _ = try await service.mkdir(url: "file:///repo/trunk/docs", message: "  ", auth: nil)
            XCTFail("Expected emptyCommitMessage")
        } catch let error as SvnServiceError {
            XCTAssertEqual(error, .emptyCommitMessage)
        } catch {
            XCTFail("Expected SvnServiceError, got \(error)")
        }

        do {
            _ = try await service.delete(url: "file:///repo/trunk/old.txt", message: "\n", auth: nil)
            XCTFail("Expected emptyCommitMessage")
        } catch let error as SvnServiceError {
            XCTAssertEqual(error, .emptyCommitMessage)
        } catch {
            XCTFail("Expected SvnServiceError, got \(error)")
        }

        do {
            _ = try await service.move(
                source: "file:///repo/trunk/old.txt",
                destination: "file:///repo/trunk/new.txt",
                message: "",
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

    func testRemoteRepositoryWritesPromptForCredentialsAndRetryOnceAfterAuthenticationFailure() async throws {
        let backend = MockSvnBackend()
        backend.mkdirErrors = [.authentication]
        backend.remoteDeleteErrors = [.authentication]
        backend.moveErrors = [.authentication]
        backend.mkdirResult = Revision(13)
        backend.remoteDeleteResult = Revision(14)
        backend.moveResult = Revision(15)
        let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
        let service = SvnService(backend: backend, credentialProvider: provider)

        let mkdirRevision = try await service.mkdir(
            url: "file:///repo/trunk/docs",
            message: "创建目录：docs",
            auth: nil
        )
        let deleteRevision = try await service.delete(
            url: "file:///repo/trunk/old.txt",
            message: "删除远端文件",
            auth: nil
        )
        let moveRevision = try await service.move(
            source: "file:///repo/trunk/old.txt",
            destination: "file:///repo/trunk/new.txt",
            message: "移动远端文件",
            auth: nil
        )
        let requestedScopes = await provider.recordedWorkingCopies()

        XCTAssertEqual([mkdirRevision, deleteRevision, moveRevision], [Revision(13), Revision(14), Revision(15)])
        XCTAssertEqual(requestedScopes, [
            URL(string: "file:///repo/trunk/docs")!,
            URL(string: "file:///repo/trunk/old.txt")!,
            URL(string: "file:///repo/trunk/new.txt")!
        ])
        XCTAssertEqual(backend.calls.map(\.name), ["mkdir", "mkdir", "remoteDelete", "remoteDelete", "move", "move"])
        XCTAssertEqual(backend.mkdirCredentials, [nil, Credential(username: "u", password: "p")])
        XCTAssertEqual(backend.remoteDeleteCredentials, [nil, Credential(username: "u", password: "p")])
        XCTAssertEqual(backend.moveCredentials, [nil, Credential(username: "u", password: "p")])
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
            revision: Revision(8),
            auth: nil,
            allowLocalChanges: true
        )

        XCTAssertEqual(summary, UpdateSummary(updated: 1, revision: Revision(9)))
        XCTAssertEqual(backend.calls.map(\.name), ["status", "switch"])
        XCTAssertEqual(backend.switchRevisions, [Revision(8)])
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

    func testMergePromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
        let backend = MockSvnBackend()
        backend.mergeErrors = [.authentication]
        backend.mergeResult = MergeSummary(updated: 1, affectedPaths: [
            MergeAffectedPath(action: .updated, path: "README.txt")
        ])
        let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
        let service = SvnService(backend: backend, credentialProvider: provider)

        let summary = try await service.merge(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            source: "file:///repo/branches/feature-one",
            range: nil,
            dryRun: true,
            auth: nil
        )
        let requestedScopes = await provider.recordedWorkingCopies()

        XCTAssertEqual(summary.updated, 1)
        XCTAssertEqual(requestedScopes, [URL(string: "file:///repo/branches/feature-one")!])
        XCTAssertEqual(backend.calls.map(\.name), ["merge", "merge"])
        XCTAssertEqual(backend.mergeCredentials, [nil, Credential(username: "u", password: "p")])
    }

    func testMergeTwoTreesForwardsSourcesAndUsesWriteOperation() async throws {
        let backend = MockSvnBackend()
        backend.mergeResult = MergeSummary(updated: 2)
        let service = SvnService(backend: backend)

        let summary = try await service.mergeTwoTrees(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            from: "file:///repo/trunk",
            to: "file:///repo/branches/feature",
            dryRun: true,
            auth: nil
        )

        XCTAssertEqual(summary, MergeSummary(updated: 2))
        XCTAssertEqual(backend.calls.map(\.name), ["mergeTwoTrees"])
    }

    func testResolveUsesBackendWriteOperation() async throws {
        let backend = MockSvnBackend()
        let service = SvnService(backend: backend)

        try await service.resolve(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            path: "README.txt",
            accept: .theirsFull
        )

        XCTAssertEqual(backend.calls.map(\.name), ["resolve"])
        XCTAssertEqual(backend.resolveAccepts, [.theirsFull])
    }

    func testApplyPatchUsesBackendWriteOperation() async throws {
        let backend = MockSvnBackend()
        let service = SvnService(backend: backend)
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let patchFile = URL(fileURLWithPath: "/tmp/shelf.patch")

        try await service.applyPatch(wc: wc, patchFile: patchFile)

        XCTAssertEqual(backend.calls.map(\.name), ["applyPatch"])
        XCTAssertEqual(backend.patchFiles, [patchFile])
    }

    func testApplyPatchWriteLockBlocksConcurrentWritesOnSameWorkingCopy() async throws {
        let backend = MockSvnBackend()
        let service = SvnService(backend: backend)
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let patchStarted = XCTestExpectation(description: "patch started")
        let releasePatch = AsyncGate()
        backend.onApplyPatch = {
            patchStarted.fulfill()
            await releasePatch.wait()
        }

        let patchTask = Task {
            try await service.applyPatch(wc: wc, patchFile: URL(fileURLWithPath: "/tmp/shelf.patch"))
        }

        await fulfillment(of: [patchStarted], timeout: 1)

        do {
            _ = try await service.update(wc: wc, paths: [], revision: nil)
            XCTFail("Expected wc busy")
        } catch let error as SvnServiceError {
            XCTAssertEqual(error, .wcBusy(operation: "patch"))
        } catch {
            XCTFail("Expected SvnServiceError, got \(error)")
        }

        await releasePatch.open()
        _ = try await patchTask.value
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

    func testRemoteLogFromHeadPromptsForCredentialsAndRetriesOnceAfterAuthenticationFailure() async throws {
        let backend = MockSvnBackend()
        backend.remoteLogFromHeadErrors = [.authentication]
        backend.remoteLogFromHeadResult = [
            LogEntry(revision: Revision(9), author: "a", date: nil, message: "m", changedPaths: [])
        ]
        let provider = FakeCredentialProvider(credential: Credential(username: "u", password: "p"))
        let service = SvnService(backend: backend, credentialProvider: provider)

        let entries = try await service.remoteLogFromHead(
            url: "file:///repo/trunk",
            batch: 10,
            verbose: true,
            auth: nil
        )
        let requestedScopes = await provider.recordedWorkingCopies()

        XCTAssertEqual(entries.map(\.revision), [Revision(9)])
        XCTAssertEqual(requestedScopes, [URL(string: "file:///repo/trunk")!])
        XCTAssertEqual(backend.calls.map(\.name), ["remoteLogFromHead", "remoteLogFromHead"])
        XCTAssertEqual(backend.remoteLogFromHeadCredentials, [nil, Credential(username: "u", password: "p")])
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

    func testCommitGuardWarningsStopCommitUntilCallerSkipsWarnings() async throws {
        let backend = MockSvnBackend()
        backend.statusResult = [
            FileStatus(path: "a.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false)
        ]
        backend.commitResult = Revision(42)
        let issue = CommitGuardIssue(
            ruleID: .conflictMarker,
            severity: .warning,
            path: "a.txt",
            message: "Conflict marker remains.",
            detail: nil
        )
        let guardProvider = FakeCommitGuardProvider(result: .success([issue]))
        let service = SvnService(backend: backend, commitGuard: guardProvider)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        do {
            _ = try await service.commit(wc: wc, paths: ["a.txt"], message: "fix", auth: nil)
            XCTFail("Expected commit guard warnings")
        } catch let error as SvnServiceError {
            XCTAssertEqual(error, .commitGuardWarnings([issue]))
        }

        let revision = try await service.commit(
            wc: wc,
            paths: ["a.txt"],
            message: "fix",
            auth: nil,
            skipGuardWarnings: true
        )

        XCTAssertEqual(revision, Revision(42))
        XCTAssertEqual(backend.calls.map(\.name), ["status", "status", "commit"])
        let guardCalls = await guardProvider.recordedCalls()
        XCTAssertEqual(guardCalls, [
            CommitGuardCall(wc: wc, paths: ["a.txt"]),
            CommitGuardCall(wc: wc, paths: ["a.txt"])
        ])
    }

    func testCommitAddsSelectedUnversionedPathsBeforeCommit() async throws {
        let backend = MockSvnBackend()
        backend.statusResult = [
            FileStatus(path: "new.txt", itemStatus: .unversioned, revision: nil, isTreeConflict: false),
            FileStatus(path: "a.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false)
        ]
        backend.commitResult = Revision(9)
        let service = SvnService(backend: backend)
        let wc = URL(fileURLWithPath: "/tmp/wc")

        let revision = try await service.commit(
            wc: wc,
            paths: ["new.txt", "a.txt"],
            message: "add and commit",
            auth: nil
        )

        XCTAssertEqual(revision, Revision(9))
        XCTAssertEqual(backend.calls.map(\.name), ["status", "add", "commit"])
        XCTAssertEqual(backend.commitKeepLocks, [false])
    }

    func testCommitKeepLocksPassesNoUnlockToBackend() async throws {
        let backend = MockSvnBackend()
        backend.statusResult = [
            FileStatus(path: "a.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false)
        ]
        backend.commitResult = Revision(3)
        let service = SvnService(backend: backend)

        _ = try await service.commit(
            wc: URL(fileURLWithPath: "/tmp/wc"),
            paths: ["a.txt"],
            message: "locked",
            auth: nil,
            keepLocks: true
        )

        XCTAssertEqual(backend.commitKeepLocks, [true])
    }

    func testCommitGuardBlockingIssuesCannotBeSkipped() async {
        let backend = MockSvnBackend()
        backend.statusResult = [
            FileStatus(path: "a.txt", itemStatus: .modified, revision: Revision(1), isTreeConflict: false)
        ]
        let issue = CommitGuardIssue(
            ruleID: .suspectedSecret,
            severity: .blocking,
            path: "a.txt",
            message: "Secret detected.",
            detail: nil
        )
        let guardProvider = FakeCommitGuardProvider(result: .success([issue]))
        let service = SvnService(backend: backend, commitGuard: guardProvider)

        do {
            _ = try await service.commit(
                wc: URL(fileURLWithPath: "/tmp/wc"),
                paths: ["a.txt"],
                message: "fix",
                auth: nil,
                skipGuardWarnings: true
            )
            XCTFail("Expected commit guard block")
        } catch let error as SvnServiceError {
            XCTAssertEqual(error, .commitGuardBlocked([issue]))
        } catch {
            XCTFail("Expected SvnServiceError, got \(error)")
        }
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
    private var recordedUpdateRevisions: [Revision?] = []
    private var recordedCommitCredentials: [Credential?] = []
    private var recordedCommitKeepLocks: [Bool] = []
    private var recordedCheckoutCredentials: [Credential?] = []
    private var recordedCheckoutDepths: [SvnDepth] = []
    private var recordedExportCredentials: [Credential?] = []
    private var recordedExportRevisions: [Revision?] = []
    private var recordedListCredentials: [Credential?] = []
    private var recordedListDepths: [SvnDepth] = []
    private var recordedCatCredentials: [Credential?] = []
    private var recordedCatSizeLimits: [Int] = []
    private var recordedRemoteLogCredentials: [Credential?] = []
    private var recordedRemoteLogFromHeadCredentials: [Credential?] = []
    private var recordedCopyCredentials: [Credential?] = []
    private var recordedMkdirCredentials: [Credential?] = []
    private var recordedRemoteDeleteCredentials: [Credential?] = []
    private var recordedMoveCredentials: [Credential?] = []
    private var recordedSwitchCredentials: [Credential?] = []
    private var recordedSwitchRevisions: [Revision?] = []
    private var recordedMergeCredentials: [Credential?] = []
    private var recordedResolveAccepts: [ResolveAccept] = []
    private var recordedPatchFiles: [URL] = []

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

    var updateRevisions: [Revision?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedUpdateRevisions
    }

    var commitCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedCommitCredentials
    }

    var commitKeepLocks: [Bool] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedCommitKeepLocks
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

    var exportCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedExportCredentials
    }

    var exportRevisions: [Revision?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedExportRevisions
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

    var remoteLogFromHeadCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedRemoteLogFromHeadCredentials
    }

    var copyCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedCopyCredentials
    }

    var mkdirCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedMkdirCredentials
    }

    var remoteDeleteCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedRemoteDeleteCredentials
    }

    var moveCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedMoveCredentials
    }

    var switchCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedSwitchCredentials
    }

    var switchRevisions: [Revision?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedSwitchRevisions
    }

    var mergeCredentials: [Credential?] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedMergeCredentials
    }

    var resolveAccepts: [ResolveAccept] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedResolveAccepts
    }

    var patchFiles: [URL] {
        callsLock.lock()
        defer {
            callsLock.unlock()
        }
        return recordedPatchFiles
    }

    var statusResult: [FileStatus] = []
    var diffResult = ""
    var blameResult: [BlameLine] = []
    var propertiesResult: [SvnProperty] = []
    var propertyValueResult: SvnProperty?
    var locksResult: [SvnLock] = []
    var logResult: [LogEntry] = []
    var infoResult = SvnInfo(path: ".", url: "file:///repo/trunk", repositoryRoot: "file:///repo", revision: Revision(1), kind: "dir")
    var headRevisionResult = Revision(99)
    var listResult: [RemoteEntry] = []
    var catResult = Data()
    var remoteLogResult: [LogEntry] = []
    var remoteLogFromHeadResult: [LogEntry] = []
    var copyResult = Revision(1)
    var mkdirResult = Revision(1)
    var remoteDeleteResult = Revision(1)
    var moveResult = Revision(1)
    var switchResult = UpdateSummary()
    var mergeResult = MergeSummary()
    var commitResult = Revision(1)
    var commitErrors: [SvnError] = []
    var updateResult = UpdateSummary()
    var updateErrors: [SvnError] = []
    var checkoutErrors: [SvnError] = []
    var exportErrors: [SvnError] = []
    var listErrors: [SvnError] = []
    var catErrors: [SvnError] = []
    var remoteLogErrors: [SvnError] = []
    var remoteLogFromHeadErrors: [SvnError] = []
    var copyErrors: [SvnError] = []
    var mkdirErrors: [SvnError] = []
    var remoteDeleteErrors: [SvnError] = []
    var moveErrors: [SvnError] = []
    var switchErrors: [SvnError] = []
    var mergeErrors: [SvnError] = []
    var onUpdate: ((URL) async -> Void)?
    var onApplyPatch: (() async -> Void)?

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

    func statusAgainstRepository(wc: URL) async throws -> [FileStatus] {
        record("statusAgainstRepository")
        return statusResult
    }

    func update(
        wc: URL,
        paths: [String],
        revision: Revision?,
        setDepth: SvnDepth?,
        ignoreExternals: Bool,
        auth: Credential?
    ) async throws -> UpdateSummary {
        let error = recordUpdate(revision: revision, setDepth: setDepth, auth: auth)
        await onUpdate?(wc)
        if let error {
            throw error
        }
        return updateResult
    }

    func commit(wc: URL, paths: [String], message: String, auth: Credential?, keepLocks: Bool) async throws -> Revision {
        let error = recordCommit(auth: auth, keepLocks: keepLocks)
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

    func moveInWorkingCopy(wc: URL, source: String, destination: String) async throws {
        record("moveInWorkingCopy")
    }

    func renameInWorkingCopy(wc: URL, source: String, destination: String) async throws {
        record("renameInWorkingCopy")
    }

    func copyInWorkingCopy(wc: URL, source: String, destination: String) async throws {
        record("copyInWorkingCopy")
    }

    func revert(wc: URL, paths: [String], recursive: Bool) async throws {
        record("revert")
    }

    func cleanup(wc: URL, options: SvnCleanupOptions) async throws {
        record("cleanup")
    }

    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        record("diff")
        return diffResult
    }

    func diffBetweenPaths(wc: URL, oldPath: String, newPath: String) async throws -> String {
        record("diffBetweenPaths")
        return diffResult
    }

    func diffAgainstBase(wc: URL, target: String) async throws -> String {
        record("diffAgainstBase")
        return diffResult
    }

    func blame(wc: URL, target: String) async throws -> [BlameLine] {
        record("blame")
        return blameResult
    }

    func properties(wc: URL, target: String) async throws -> [SvnProperty] {
        record("properties")
        return propertiesResult
    }

    func propertyValue(wc: URL, target: String, name: String) async throws -> SvnProperty? {
        record("propertyValue")
        return propertyValueResult
    }

    func setProperty(wc: URL, target: String, name: String, value: String) async throws {
        record("setProperty")
    }

    func deleteProperty(wc: URL, target: String, name: String) async throws {
        record("deleteProperty")
    }

    func locks(wc: URL, targets: [String]) async throws -> [SvnLock] {
        record("locks")
        return locksResult
    }

    func lock(wc: URL, paths: [String], message: String?, force: Bool) async throws {
        record("lock")
    }

    func unlock(wc: URL, paths: [String], force: Bool) async throws {
        record("unlock")
    }

    func log(
        wc: URL,
        target: String,
        from: Revision,
        batch: Int,
        verbose: Bool,
        stopOnCopy: Bool
    ) async throws -> [LogEntry] {
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

    func remoteLogFromHead(url: String, batch: Int, verbose: Bool, auth: Credential?) async throws -> [LogEntry] {
        let error = recordRemoteLogFromHead(auth: auth)
        if let error {
            throw error
        }
        return remoteLogFromHeadResult
    }

    func checkout(
        url: String,
        to destination: URL,
        depth: SvnDepth,
        revision: Revision?,
        ignoreExternals: Bool,
        auth: Credential?
    ) async throws {
        let error = recordCheckout(depth: depth, auth: auth)
        _ = revision
        _ = ignoreExternals
        if let error {
            throw error
        }
    }

    func export(url: String, to destination: URL, revision: Revision?, auth: Credential?) async throws {
        let error = recordExport(revision: revision, auth: auth)
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

    func mkdir(url: String, message: String, auth: Credential?) async throws -> Revision {
        let error = recordRemoteWrite(name: "mkdir", credentials: &recordedMkdirCredentials, errors: &mkdirErrors, auth: auth)
        if let error {
            throw error
        }
        return mkdirResult
    }

    func delete(url: String, message: String, auth: Credential?) async throws -> Revision {
        let error = recordRemoteWrite(
            name: "remoteDelete",
            credentials: &recordedRemoteDeleteCredentials,
            errors: &remoteDeleteErrors,
            auth: auth
        )
        if let error {
            throw error
        }
        return remoteDeleteResult
    }

    func move(source: String, destination: String, message: String, auth: Credential?) async throws -> Revision {
        let error = recordRemoteWrite(name: "move", credentials: &recordedMoveCredentials, errors: &moveErrors, auth: auth)
        if let error {
            throw error
        }
        return moveResult
    }

    func switchTo(wc: URL, url: String, revision: Revision?, auth: Credential?) async throws -> UpdateSummary {
        let error = recordSwitch(revision: revision, auth: auth)
        if let error {
            throw error
        }
        return switchResult
    }

    func merge(
        wc: URL,
        source: String,
        range: RevisionRange?,
        dryRun: Bool,
        auth: Credential?
    ) async throws -> MergeSummary {
        let error = recordMerge(auth: auth)
        if let error {
            throw error
        }
        return mergeResult
    }

    func mergeTwoTrees(
        wc: URL,
        from: String,
        to: String,
        dryRun: Bool,
        auth: Credential?
    ) async throws -> MergeSummary {
        _ = from
        _ = to
        _ = dryRun
        let error = recordMerge(auth: auth, name: "mergeTwoTrees")
        if let error {
            throw error
        }
        return mergeResult
    }

    func resolve(wc: URL, path: String, accept: ResolveAccept) async throws {
        recordResolve(accept: accept)
    }

    func applyPatch(wc: URL, patchFile: URL) async throws {
        recordApplyPatch(patchFile: patchFile)
        await onApplyPatch?()
    }

    private func recordResolve(accept: ResolveAccept) {
        callsLock.lock()
        recordedCalls.append(Call(name: "resolve"))
        recordedResolveAccepts.append(accept)
        callsLock.unlock()
    }

    private func recordApplyPatch(patchFile: URL) {
        callsLock.lock()
        recordedCalls.append(Call(name: "applyPatch"))
        recordedPatchFiles.append(patchFile)
        callsLock.unlock()
    }

    func info(wc: URL, target: String) async throws -> SvnInfo {
        record("info")
        return infoResult
    }

    func repositoryHeadRevision(wc: URL, target: String) async throws -> Revision {
        record("repositoryHeadRevision")
        return headRevisionResult
    }

    private func recordUpdate(revision: Revision?, setDepth: SvnDepth?, auth: Credential?) -> SvnError? {
        callsLock.lock()
        recordedCalls.append(Call(name: "update"))
        recordedUpdateRevisions.append(revision)
        recordedUpdateSetDepths.append(setDepth)
        recordedUpdateCredentials.append(auth)
        let error = updateErrors.isEmpty ? nil : updateErrors.removeFirst()
        callsLock.unlock()
        return error
    }

    private func recordCommit(auth: Credential?, keepLocks: Bool = false) -> SvnError? {
        callsLock.lock()
        recordedCalls.append(Call(name: "commit"))
        recordedCommitCredentials.append(auth)
        recordedCommitKeepLocks.append(keepLocks)
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

    private func recordExport(revision: Revision?, auth: Credential?) -> SvnError? {
        callsLock.lock()
        recordedCalls.append(Call(name: "export"))
        recordedExportRevisions.append(revision)
        recordedExportCredentials.append(auth)
        let error = exportErrors.isEmpty ? nil : exportErrors.removeFirst()
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

    private func recordRemoteLogFromHead(auth: Credential?) -> SvnError? {
        callsLock.lock()
        recordedCalls.append(Call(name: "remoteLogFromHead"))
        recordedRemoteLogFromHeadCredentials.append(auth)
        let error = remoteLogFromHeadErrors.isEmpty ? nil : remoteLogFromHeadErrors.removeFirst()
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

    private func recordRemoteWrite(
        name: String,
        credentials: inout [Credential?],
        errors: inout [SvnError],
        auth: Credential?
    ) -> SvnError? {
        callsLock.lock()
        recordedCalls.append(Call(name: name))
        credentials.append(auth)
        let error = errors.isEmpty ? nil : errors.removeFirst()
        callsLock.unlock()
        return error
    }

    private func recordSwitch(revision: Revision?, auth: Credential?) -> SvnError? {
        callsLock.lock()
        recordedCalls.append(Call(name: "switch"))
        recordedSwitchCredentials.append(auth)
        recordedSwitchRevisions.append(revision)
        let error = switchErrors.isEmpty ? nil : switchErrors.removeFirst()
        callsLock.unlock()
        return error
    }

    private func recordMerge(auth: Credential?, name: String = "merge") -> SvnError? {
        callsLock.lock()
        recordedCalls.append(Call(name: name))
        recordedMergeCredentials.append(auth)
        let error = mergeErrors.isEmpty ? nil : mergeErrors.removeFirst()
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

private struct CommitGuardCall: Equatable, Sendable {
    let wc: URL
    let paths: [String]
}

private actor FakeCommitGuardProvider: CommitGuardChecking {
    private let result: Result<[CommitGuardIssue], Error>
    private var calls: [CommitGuardCall] = []

    init(result: Result<[CommitGuardIssue], Error>) {
        self.result = result
    }

    func evaluate(wc: URL, paths: [String]) async throws -> [CommitGuardIssue] {
        calls.append(CommitGuardCall(wc: wc, paths: paths))
        return try result.get()
    }

    func recordedCalls() -> [CommitGuardCall] {
        calls
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
