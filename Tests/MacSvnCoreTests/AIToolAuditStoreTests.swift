import Foundation
import XCTest
@testable import MacSvnCore

final class AIToolAuditStoreTests: XCTestCase {
    func testAppendPersistsRecordsAndReloadsBySession() async throws {
        let fileURL = try makeTemporaryDirectory().appendingPathComponent("ai-tool-audit.json")
        let first = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sessionID: "session-a",
            toolName: "svn_status",
            outcome: .completed,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let second = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            sessionID: "session-b",
            toolName: "svn_revert",
            risk: .highRiskWrite,
            outcome: .confirmationRequired,
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let store = AIToolAuditStore(fileURL: fileURL)

        await store.append(first)
        await store.append(second)
        let reloaded = AIToolAuditStore(fileURL: fileURL)

        let allRecords = try await reloaded.records()
        let sessionARecords = try await reloaded.records(sessionID: "session-a")

        XCTAssertEqual(allRecords, [first, second])
        XCTAssertEqual(sessionARecords, [first])
    }

    func testExportJSONCanFilterBySession() async throws {
        let fileURL = try makeTemporaryDirectory().appendingPathComponent("ai-tool-audit.json")
        let first = makeRecord(sessionID: "session-a", toolName: "svn_status", outcome: .completed)
        let second = makeRecord(sessionID: "session-b", toolName: "svn_info", outcome: .completed)
        let store = AIToolAuditStore(fileURL: fileURL)
        await store.append(first)
        await store.append(second)

        let data = try await store.exportJSON(sessionID: "session-b")
        let exported = try JSONDecoder.auditDecoder.decode([AISVNToolAuditRecord].self, from: data)

        XCTAssertEqual(exported, [second])
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("svn_info"))
    }

    func testRegistryPersistsCompletedConfirmationAndFailedAuditRecords() async throws {
        let fileURL = try makeTemporaryDirectory().appendingPathComponent("ai-tool-audit.json")
        let auditStore = AIToolAuditStore(fileURL: fileURL)
        let service = FakeAuditToolService(statusResult: [
            FileStatus(path: "README.md", itemStatus: .modified, revision: Revision(7), isTreeConflict: false)
        ])
        let registry = AISVNToolRegistry(service: service, auditStore: auditStore)

        _ = try await registry.handle(
            AISVNToolCall(name: "svn_status", arguments: ["wc": "/tmp/wc"]),
            sessionID: "session-registry"
        )
        _ = try await registry.handle(
            AISVNToolCall(name: "svn_revert", arguments: ["wc": "/tmp/wc", "paths": "README.md"]),
            sessionID: "session-registry"
        )
        do {
            _ = try await registry.handle(
                AISVNToolCall(name: "shell_exec", arguments: ["command": "whoami"]),
                sessionID: "session-registry"
            )
            XCTFail("Expected forbidden tool")
        } catch let error as AISVNToolError {
            XCTAssertEqual(error, .forbiddenTool("shell_exec"))
        }

        let reloaded = AIToolAuditStore(fileURL: fileURL)
        let records = try await reloaded.records(sessionID: "session-registry")

        XCTAssertEqual(records.map(\.toolName), ["svn_status", "svn_revert", "shell_exec"])
        XCTAssertEqual(records.map(\.outcome), [.completed, .confirmationRequired, .failed])
        XCTAssertEqual(records.map(\.risk), [.readOnly, .highRiskWrite, nil])
    }

    private func makeRecord(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
        sessionID: String,
        toolName: String,
        risk: AISVNToolRisk? = .readOnly,
        outcome: AISVNToolAuditOutcome,
        createdAt: Date = Date(timeIntervalSince1970: 30)
    ) -> AISVNToolAuditRecord {
        AISVNToolAuditRecord(
            id: id,
            sessionID: sessionID,
            toolName: toolName,
            risk: risk,
            arguments: ["wc": "/tmp/wc"],
            outcome: outcome,
            summary: "summary",
            createdAt: createdAt
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private actor FakeAuditToolService: AISVNToolServicing {
    var statusResult: [FileStatus]

    init(statusResult: [FileStatus] = []) {
        self.statusResult = statusResult
    }

    func status(wc: URL) async throws -> [FileStatus] {
        statusResult
    }

    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String {
        ""
    }

    func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry] {
        []
    }

    func info(wc: URL, target: String) async throws -> SvnInfo {
        SvnInfo(
            path: target,
            url: "file:///repo/trunk",
            repositoryRoot: "file:///repo",
            revision: Revision(1),
            kind: "dir"
        )
    }

    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry] {
        []
    }

    func blame(wc: URL, target: String) async throws -> [BlameLine] {
        []
    }

    func cat(url: String, revision: Revision?, sizeLimit: Int, auth: Credential?) async throws -> Data {
        Data()
    }
}

private extension JSONDecoder {
    static var auditDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
