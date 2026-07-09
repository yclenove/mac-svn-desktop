import Foundation
import XCTest
@testable import MacSvnCore

final class CommitMessageHistoryStoreTests: XCTestCase {
    func testRecordMessageStoresRecentUniqueMessagesPerWorkingCopyWithLimitTen() async throws {
        let fileURL = try makeTemporaryDirectory().appendingPathComponent("commit-history.json")
        let store = CommitMessageHistoryStore(fileURL: fileURL)
        let wcA = URL(fileURLWithPath: "/tmp/project-a")
        let wcB = URL(fileURLWithPath: "/tmp/project-b")

        for index in 1...11 {
            try await store.record(message: "message \(index)", workingCopy: wcA)
        }
        try await store.record(message: "message 8", workingCopy: wcA)
        try await store.record(message: "other", workingCopy: wcB)

        let messagesA = try await store.recentMessages(workingCopy: wcA)
        let messagesB = try await store.recentMessages(workingCopy: wcB)

        XCTAssertEqual(messagesA, [
            "message 8",
            "message 11",
            "message 10",
            "message 9",
            "message 7",
            "message 6",
            "message 5",
            "message 4",
            "message 3",
            "message 2"
        ])
        XCTAssertEqual(messagesB, ["other"])
    }

    func testRecordRejectsBlankMessagesAndPersistsToDisk() async throws {
        let fileURL = try makeTemporaryDirectory().appendingPathComponent("commit-history.json")
        let store = CommitMessageHistoryStore(fileURL: fileURL)
        let wc = URL(fileURLWithPath: "/tmp/project")

        try await store.record(message: "  修复登录  \n", workingCopy: wc)
        do {
            try await store.record(message: "   ", workingCopy: wc)
            XCTFail("Expected blank message rejection")
        } catch let error as CommitMessageHistoryStoreError {
            XCTAssertEqual(error, .emptyMessage)
        }

        let reloaded = CommitMessageHistoryStore(fileURL: fileURL)
        let messages = try await reloaded.recentMessages(workingCopy: wc)

        XCTAssertEqual(messages, ["修复登录"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
