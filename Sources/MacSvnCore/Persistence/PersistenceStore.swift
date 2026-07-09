import Foundation

public struct PersistenceStore<Value: Codable> {
    private let fileURL: URL
    private let defaultValue: Value
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL, defaultValue: Value) {
        self.fileURL = fileURL
        self.defaultValue = defaultValue

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() throws -> Value {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return defaultValue
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try encoder.encode(value)
        try data.write(to: fileURL, options: .atomic)
    }
}
