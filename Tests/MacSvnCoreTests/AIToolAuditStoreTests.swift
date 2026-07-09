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

private extension JSONDecoder {
    static var auditDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
