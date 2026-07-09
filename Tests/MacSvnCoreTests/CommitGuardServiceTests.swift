import XCTest
@testable import MacSvnCore

final class CommitGuardServiceTests: XCTestCase {
    func testDetectsConflictMarkersLargeFilesDeniedPathsAndSecrets() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "before\n<<<<<<< mine\n=======\n>>>>>>> theirs\n".write(
            to: root.appendingPathComponent("conflict.txt"),
            atomically: true,
            encoding: .utf8
        )
        try Data(repeating: 0x61, count: 1025).write(to: root.appendingPathComponent("big.bin"))
        try "debug\n".write(to: root.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)
        try "token = ghp_123456789012345678901234567890123456\n".write(
            to: root.appendingPathComponent("secret.txt"),
            atomically: true,
            encoding: .utf8
        )
        let service = CommitGuardService(configuration: CommitGuardConfiguration(largeFileThresholdBytes: 1024))

        let issues = try await service.evaluate(
            wc: root,
            paths: ["conflict.txt", "big.bin", "debug.log", "secret.txt"]
        )

        XCTAssertEqual(issues.map(\.ruleID), [
            .conflictMarker,
            .largeFile,
            .deniedPath,
            .suspectedSecret
        ])
        XCTAssertEqual(issues.map(\.severity), [.warning, .warning, .warning, .warning])
        XCTAssertEqual(issues.map(\.path), ["conflict.txt", "big.bin", "debug.log", "secret.txt"])
    }

    func testHardBlockedRulesProduceBlockingSeverity() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try "token = sk-123456789012345678901234567890\n".write(
            to: root.appendingPathComponent("secret.txt"),
            atomically: true,
            encoding: .utf8
        )
        let config = CommitGuardConfiguration(hardBlockedRules: [.suspectedSecret])
        let service = CommitGuardService(configuration: config)

        let issues = try await service.evaluate(wc: root, paths: ["secret.txt"])

        XCTAssertEqual(issues.first?.ruleID, .suspectedSecret)
        XCTAssertEqual(issues.first?.severity, .blocking)
    }

    func testMissingDirectoriesAndDeletedPathsAreIgnored() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        let service = CommitGuardService()

        let issues = try await service.evaluate(wc: root, paths: ["src", "deleted.txt"])

        XCTAssertEqual(issues, [])
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
