import XCTest
@testable import MacSvnApp

final class MacSvnProjectPropertyLoaderTests: XCTestCase {
    func testAncestorTargetsUseCommonDirectoryFromRootToNearestAncestor() throws {
        let workingCopy = try makeWorkingCopy()
        defer { try? FileManager.default.removeItem(at: workingCopy) }
        try writeFile("Sources/App/Main.swift", in: workingCopy)
        try writeFile("Sources/App/Views/CommitView.swift", in: workingCopy)

        XCTAssertEqual(
            MacSvnProjectPropertyLoader.ancestorTargets(for: [
                "Sources/App/Main.swift",
                "Sources/App/Views/CommitView.swift"
            ], workingCopy: workingCopy),
            [".", "Sources", "Sources/App"]
        )
    }

    func testAncestorTargetsFallbackToRootForMixedTopLevelPaths() throws {
        let workingCopy = try makeWorkingCopy()
        defer { try? FileManager.default.removeItem(at: workingCopy) }
        try writeFile("Sources/App/Main.swift", in: workingCopy)
        try writeFile("Tests/AppTests/MainTests.swift", in: workingCopy)

        XCTAssertEqual(
            MacSvnProjectPropertyLoader.ancestorTargets(for: [
                "Sources/App/Main.swift",
                "Tests/AppTests/MainTests.swift"
            ], workingCopy: workingCopy),
            ["."]
        )
    }

    func testAncestorTargetsTreatsExistingExtensionlessPathAsFile() throws {
        let workingCopy = try makeWorkingCopy()
        defer { try? FileManager.default.removeItem(at: workingCopy) }
        try writeFile("README", in: workingCopy)

        XCTAssertEqual(
            MacSvnProjectPropertyLoader.ancestorTargets(for: ["README"], workingCopy: workingCopy),
            ["."]
        )
    }

    func testAncestorTargetsIncludesExistingDirectoryWithExtension() throws {
        let workingCopy = try makeWorkingCopy()
        defer { try? FileManager.default.removeItem(at: workingCopy) }
        try FileManager.default.createDirectory(
            at: workingCopy.appendingPathComponent("Modules/Foo.framework"),
            withIntermediateDirectories: true
        )

        XCTAssertEqual(
            MacSvnProjectPropertyLoader.ancestorTargets(
                for: ["Modules/Foo.framework"],
                workingCopy: workingCopy
            ),
            [".", "Modules", "Modules/Foo.framework"]
        )
    }

    func testAncestorTargetChainsKeepEverySelectedDirectoryHierarchy() throws {
        let workingCopy = try makeWorkingCopy()
        defer { try? FileManager.default.removeItem(at: workingCopy) }
        try writeFile("Features/A/file.swift", in: workingCopy)
        try writeFile("Features/B/file.swift", in: workingCopy)

        XCTAssertEqual(
            MacSvnProjectPropertyLoader.ancestorTargetChains(
                for: ["Features/A/file.swift", "Features/B/file.swift"],
                workingCopy: workingCopy
            ),
            [
                [".", "Features", "Features/A"],
                [".", "Features", "Features/B"]
            ]
        )
    }

    private func makeWorkingCopy() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeFile(_ relativePath: String, in workingCopy: URL) throws {
        let fileURL = workingCopy.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: fileURL)
    }
}
