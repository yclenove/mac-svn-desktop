import Foundation
import XCTest
@testable import MacSvnCore

final class PersistenceStoreTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testReadMissingFileReturnsDefaultValue() throws {
        let store = PersistenceStore<SamplePayload>(
            fileURL: temporaryRoot().appendingPathComponent("sample.json"),
            defaultValue: SamplePayload(version: 1, names: [])
        )

        XCTAssertEqual(try store.load(), SamplePayload(version: 1, names: []))
    }

    func testSaveAndLoadRoundTripsJSON() throws {
        let store = PersistenceStore<SamplePayload>(
            fileURL: temporaryRoot().appendingPathComponent("nested/sample.json"),
            defaultValue: SamplePayload(version: 1, names: [])
        )
        let payload = SamplePayload(version: 1, names: ["中文", "space name"])

        try store.save(payload)

        XCTAssertEqual(try store.load(), payload)
    }

    private func temporaryRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSvnCorePersistence-\(UUID().uuidString)", isDirectory: true)
        temporaryRoots.append(root)
        return root
    }
}

private struct SamplePayload: Codable, Equatable {
    let version: Int
    let names: [String]
}
