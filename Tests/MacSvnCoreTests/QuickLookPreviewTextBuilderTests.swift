import XCTest
@testable import MacSvnCore

final class QuickLookPreviewTextBuilderTests: XCTestCase {
    func testBuildsDiffPreviewInsideWorkingCopy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ql-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".svn"), withIntermediateDirectories: true)
        let file = root.appendingPathComponent("a.txt")
        try "hello\n".write(to: file, atomically: true, encoding: .utf8)

        let builder = QuickLookPreviewTextBuilder(diffRunner: { _, target in
            XCTAssertEqual(target, "a.txt")
            return .ok("Index: a.txt\n+hello\n")
        })
        let text = builder.build(for: file)
        XCTAssertTrue(text.contains("+hello"))
        XCTAssertTrue(text.contains("a.txt"))
    }

    func testReportsBinaryAndOutsideWorkingCopy() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-in-wc-\(UUID().uuidString).txt")
        try "outside\n".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }

        let builder = QuickLookPreviewTextBuilder(diffRunner: { _, _ in .ok("") })
        let text = builder.build(for: outside)
        XCTAssertTrue(text.contains("工作副本") || text.contains("无法"), text)

        let builder2 = QuickLookPreviewTextBuilder(diffRunner: { _, _ in
            .ok("Cannot display: file marked as a binary type.\n")
        })
        let wc = FileManager.default.temporaryDirectory.appendingPathComponent("ql-bin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: wc.appendingPathComponent(".svn"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: wc) }
        let file = wc.appendingPathComponent("x.bin")
        try Data([1, 2, 3]).write(to: file)
        let binaryText = builder2.build(for: file, preferredRoots: [wc.path])
        XCTAssertTrue(binaryText.contains("二进制"), binaryText)
    }

    func testConflictHintWhenMineSiblingExists() throws {
        let wc = FileManager.default.temporaryDirectory.appendingPathComponent("ql-cf-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: wc) }
        try FileManager.default.createDirectory(at: wc.appendingPathComponent(".svn"), withIntermediateDirectories: true)
        let file = wc.appendingPathComponent("c.txt")
        try "mine\n".write(to: file, atomically: true, encoding: .utf8)
        try "mine side\n".write(to: URL(fileURLWithPath: file.path + ".mine"), atomically: true, encoding: .utf8)
        try "theirs\n".write(to: URL(fileURLWithPath: file.path + ".r2"), atomically: true, encoding: .utf8)

        let builder = QuickLookPreviewTextBuilder(diffRunner: { _, _ in .ok("") })
        let text = builder.build(for: file, preferredRoots: [wc.path])
        XCTAssertTrue(text.contains("冲突"))
        XCTAssertTrue(text.contains(".mine"))
    }
}
