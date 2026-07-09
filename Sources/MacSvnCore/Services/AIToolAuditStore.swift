import Foundation

private struct AIToolAuditLogFile: Codable, Sendable {
    var version: Int
    var records: [AISVNToolAuditRecord]

    init(version: Int = 1, records: [AISVNToolAuditRecord] = []) {
        self.version = version
        self.records = records
    }
}

public actor AIToolAuditStore: AIToolAuditing {
    private let store: PersistenceStore<AIToolAuditLogFile>

    public init(fileURL: URL) {
        self.store = PersistenceStore(fileURL: fileURL, defaultValue: AIToolAuditLogFile())
    }

    public func append(_ record: AISVNToolAuditRecord) {
        do {
            var file = try store.load()
            file.records.append(record)
            try store.save(file)
        } catch {
            // Audit failures should not interrupt SVN tool handling.
        }
    }

    public func records() async throws -> [AISVNToolAuditRecord] {
        try store.load().records
    }

    public func records(sessionID: String) async throws -> [AISVNToolAuditRecord] {
        try store.load().records.filter { $0.sessionID == sessionID }
    }

    public func exportJSON(sessionID: String? = nil) async throws -> Data {
        let allRecords = try store.load().records
        let exported = sessionID.map { sessionID in
            allRecords.filter { $0.sessionID == sessionID }
        } ?? allRecords
        return try Self.exportEncoder.encode(exported)
    }

    private static var exportEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
