import XCTest
@testable import MacSvnCore

final class MergeInfoServiceTests: XCTestCase {
    func testLoadsSvnMergeInfoPropertyAndParsesEntries() async throws {
        let wc = URL(fileURLWithPath: "/tmp/wc")
        let provider = FakeMergeInfoPropertyProvider(
            property: SvnProperty(
                target: ".",
                name: "svn:mergeinfo",
                value: "/branches/feature-a:2-3,5\n"
            )
        )
        let service = MergeInfoService(propertyProvider: provider)

        let entries = try await service.mergeInfo(wc: wc, target: ".")

        XCTAssertEqual(entries, [
            MergeInfoEntry(
                sourcePath: "/branches/feature-a",
                ranges: [
                    MergeInfoRevisionRange(start: Revision(2), end: Revision(3)),
                    MergeInfoRevisionRange(start: Revision(5), end: Revision(5))
                ]
            )
        ])
        let calls = await provider.recordedCalls()
        XCTAssertEqual(calls, [
            MergeInfoPropertyCall(wc: wc, target: ".", name: "svn:mergeinfo")
        ])
    }

    func testMissingSvnMergeInfoPropertyReturnsNoEntries() async throws {
        let service = MergeInfoService(propertyProvider: FakeMergeInfoPropertyProvider(property: nil))

        let entries = try await service.mergeInfo(wc: URL(fileURLWithPath: "/tmp/wc"), target: ".")

        XCTAssertEqual(entries, [])
    }
}

private struct MergeInfoPropertyCall: Equatable, Sendable {
    let wc: URL
    let target: String
    let name: String
}

private actor FakeMergeInfoPropertyProvider: MergeInfoPropertyProviding {
    private let property: SvnProperty?
    private var calls: [MergeInfoPropertyCall] = []

    init(property: SvnProperty?) {
        self.property = property
    }

    func recordedCalls() -> [MergeInfoPropertyCall] {
        calls
    }

    func propertyValue(wc: URL, target: String, name: String) async throws -> SvnProperty? {
        calls.append(MergeInfoPropertyCall(wc: wc, target: target, name: name))
        return property
    }
}
