import XCTest
@testable import MacSvnCore

final class AISVNToolRegistryTests: XCTestCase {
    func testToolNamesClassifyReadOnlyLowRiskAndHighRiskTools() {
        XCTAssertEqual(AISVNToolName.svnStatus.risk, .readOnly)
        XCTAssertEqual(AISVNToolName.svnLog.risk, .readOnly)
        XCTAssertEqual(AISVNToolName.svnDiff.risk, .readOnly)
        XCTAssertEqual(AISVNToolName.svnInfo.risk, .readOnly)
        XCTAssertEqual(AISVNToolName.svnList.risk, .readOnly)
        XCTAssertEqual(AISVNToolName.svnBlame.risk, .readOnly)
        XCTAssertEqual(AISVNToolName.svnCat.risk, .readOnly)

        XCTAssertEqual(AISVNToolName.svnUpdate.risk, .lowRiskWrite)
        XCTAssertEqual(AISVNToolName.svnAdd.risk, .lowRiskWrite)
        XCTAssertEqual(AISVNToolName.svnCleanup.risk, .lowRiskWrite)

        XCTAssertEqual(AISVNToolName.svnCommit.risk, .highRiskWrite)
        XCTAssertEqual(AISVNToolName.svnRevert.risk, .highRiskWrite)
        XCTAssertEqual(AISVNToolName.svnMerge.risk, .highRiskWrite)
        XCTAssertEqual(AISVNToolName.svnSwitch.risk, .highRiskWrite)
        XCTAssertEqual(AISVNToolName.svnDelete.risk, .highRiskWrite)
        XCTAssertEqual(AISVNToolName.svnCopy.risk, .highRiskWrite)
    }

    func testReadOnlyStatusExecutesThroughServiceAndWritesAuditRecord() async throws {
        let service = FakeAISVNToolService(statusResult: [
            FileStatus(path: "README.md", itemStatus: .modified, revision: Revision(7), isTreeConflict: false)
        ])
        let audit = InMemoryAIToolAuditStore()
        let registry = AISVNToolRegistry(service: service, auditStore: audit)

        let decision = try await registry.handle(
            AISVNToolCall(name: "svn_status", arguments: ["wc": "/tmp/wc"]),
            sessionID: "session-1"
        )

        guard case .completed(let result) = decision else {
            return XCTFail("Expected completed result")
        }
        XCTAssertTrue(result.content.contains("README.md"))
        let serviceCalls = await service.recordedCalls()
        XCTAssertEqual(serviceCalls, ["status:/tmp/wc"])
        let records = await audit.records(sessionID: "session-1")
        XCTAssertEqual(records.map(\.toolName), ["svn_status"])
        XCTAssertEqual(records.map(\.risk), [.readOnly])
        XCTAssertEqual(records.map(\.outcome), [.completed])
    }

    func testWriteToolsReturnConfirmationWithoutExecutingService() async throws {
        let service = FakeAISVNToolService()
        let audit = InMemoryAIToolAuditStore()
        let registry = AISVNToolRegistry(service: service, auditStore: audit)

        let lowRisk = try await registry.handle(
            AISVNToolCall(name: "svn_update", arguments: ["wc": "/tmp/wc", "paths": "README.md,Sources/App.swift"]),
            sessionID: "session-2"
        )
        let highRisk = try await registry.handle(
            AISVNToolCall(name: "svn_revert", arguments: ["wc": "/tmp/wc", "paths": "README.md"]),
            sessionID: "session-2"
        )

        guard case .confirmationRequired(let updateConfirmation) = lowRisk,
              case .confirmationRequired(let revertConfirmation) = highRisk else {
            return XCTFail("Expected confirmation requests")
        }
        XCTAssertEqual(updateConfirmation.risk, .lowRiskWrite)
        XCTAssertEqual(updateConfirmation.impactPaths, ["README.md", "Sources/App.swift"])
        XCTAssertTrue(updateConfirmation.commandPreview.contains("svn update"))
        XCTAssertEqual(revertConfirmation.risk, .highRiskWrite)
        XCTAssertEqual(revertConfirmation.impactPaths, ["README.md"])
        XCTAssertTrue(revertConfirmation.warning.contains("高危"))
        let serviceCalls = await service.recordedCalls()
        XCTAssertEqual(serviceCalls, [])
        let records = await audit.records(sessionID: "session-2")
        XCTAssertEqual(records.map(\.outcome), [.confirmationRequired, .confirmationRequired])
    }
}

private actor FakeAISVNToolService: AISVNToolServicing {
    var statusResult: [FileStatus]
    var diffResult = ""
    var logResult: [LogEntry] = []
    var infoResult = SvnInfo(path: ".", url: "file:///repo/trunk", repositoryRoot: "file:///repo", revision: Revision(1), kind: "dir")
    var listResult: [RemoteEntry] = []
    var blameResult: [BlameLine] = []
    var catResult = Data()
    private var calls: [String] = []

    init(statusResult: [FileStatus] = []) {
        self.statusResult = statusResult
    }

    func recordedCalls() -> [String] {
        calls
    }

    func status(wc: URL) async throws -> [FileStatus] {
        calls.append("status:\(wc.path)")
        return statusResult
    }

    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        calls.append("diff:\(wc.path):\(target)")
        return diffResult
    }

    func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry] {
        calls.append("log:\(wc.path):\(target)")
        return logResult
    }

    func info(wc: URL, target: String) async throws -> SvnInfo {
        calls.append("info:\(wc.path):\(target)")
        return infoResult
    }

    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry] {
        calls.append("list:\(url)")
        return listResult
    }

    func blame(wc: URL, target: String) async throws -> [BlameLine] {
        calls.append("blame:\(wc.path):\(target)")
        return blameResult
    }

    func cat(url: String, revision: Revision?, sizeLimit: Int, auth: Credential?) async throws -> Data {
        calls.append("cat:\(url)")
        return catResult
    }
}
