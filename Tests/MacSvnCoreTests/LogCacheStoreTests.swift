import Foundation
import XCTest
@testable import MacSvnCore

final class LogCacheStoreTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testMergePersistsDeduplicatesAndCapsEntriesPerKey() async throws {
        let file = temporaryFile()
        let key = LogCacheKey(repositoryRoot: "file:///repo", target: "trunk", stopOnCopy: false)
        let policy = LogCachePolicy(enabled: true, retentionDays: 30, maxEntriesPerTarget: 3)
        let now = Date(timeIntervalSince1970: 10_000)
        let store = LogCacheStore(fileURL: file)

        try await store.merge(
            entries: [cacheEntry(5, message: "old"), cacheEntry(4), cacheEntry(3)],
            for: key,
            policy: policy,
            now: now
        )
        try await store.merge(
            entries: [cacheEntry(6), cacheEntry(5, message: "new")],
            for: key,
            policy: policy,
            now: now.addingTimeInterval(10)
        )

        let reloaded = LogCacheStore(fileURL: file)
        let snapshot = try await reloaded.snapshot(for: key, policy: policy, now: now.addingTimeInterval(20))
        XCTAssertEqual(snapshot?.entries.map(\.revision.value), [6, 5, 4])
        XCTAssertEqual(snapshot?.entries.first(where: { $0.revision == Revision(5) })?.message, "new")
        XCTAssertEqual(snapshot?.updatedAt, now.addingTimeInterval(10))
    }

    func testSnapshotPrunesExpiredTargetsAndKeepsKeysIsolated() async throws {
        let store = LogCacheStore(fileURL: temporaryFile())
        let oldKey = LogCacheKey(repositoryRoot: "file:///old", target: "trunk", stopOnCopy: false)
        let liveKey = LogCacheKey(repositoryRoot: "file:///live", target: "branches/x", stopOnCopy: true)
        let policy = LogCachePolicy(enabled: true, retentionDays: 7, maxEntriesPerTarget: 100)
        let now = Date(timeIntervalSince1970: 20 * 86_400)

        try await store.merge(entries: [cacheEntry(1)], for: oldKey, policy: policy, now: now.addingTimeInterval(-8 * 86_400))
        try await store.merge(entries: [cacheEntry(2)], for: liveKey, policy: policy, now: now)

        let oldSnapshot = try await store.snapshot(for: oldKey, policy: policy, now: now)
        XCTAssertNil(oldSnapshot)
        let liveSnapshot = try await store.snapshot(for: liveKey, policy: policy, now: now)
        XCTAssertEqual(
            liveSnapshot?.entries.map(\.revision.value),
            [2]
        )
        let overview = try await store.overview(policy: policy, now: now)
        XCTAssertEqual(overview.targetCount, 1)
        XCTAssertEqual(overview.entryCount, 1)
    }

    func testSnapshotAppliesLoweredEntryLimitToExistingCache() async throws {
        let store = LogCacheStore(fileURL: temporaryFile())
        let key = LogCacheKey(repositoryRoot: "file:///repo", target: "trunk", stopOnCopy: false)
        let originalPolicy = LogCachePolicy(enabled: true, retentionDays: 30, maxEntriesPerTarget: 5)
        let loweredPolicy = LogCachePolicy(enabled: true, retentionDays: 30, maxEntriesPerTarget: 2)
        let now = Date(timeIntervalSince1970: 10_000)

        try await store.merge(
            entries: [cacheEntry(5), cacheEntry(4), cacheEntry(3), cacheEntry(2)],
            for: key,
            policy: originalPolicy,
            now: now
        )

        let snapshot = try await store.snapshot(for: key, policy: loweredPolicy, now: now)

        XCTAssertEqual(snapshot?.entries.map(\.revision.value), [5, 4])
        let overview = try await store.overview(policy: loweredPolicy, now: now)
        XCTAssertEqual(overview.entryCount, 2)
    }

    func testDisabledPolicySkipsWritesAndClearSupportsTargetAndAll() async throws {
        let store = LogCacheStore(fileURL: temporaryFile())
        let first = LogCacheKey(repositoryRoot: "file:///repo", target: "trunk", stopOnCopy: false)
        let second = LogCacheKey(repositoryRoot: "file:///repo", target: "tags", stopOnCopy: false)
        let enabled = LogCachePolicy(enabled: true, retentionDays: 30, maxEntriesPerTarget: 100)
        let disabled = LogCachePolicy(enabled: false, retentionDays: 30, maxEntriesPerTarget: 100)
        let now = Date(timeIntervalSince1970: 1_000)

        try await store.merge(entries: [cacheEntry(1)], for: first, policy: disabled, now: now)
        let disabledSnapshot = try await store.snapshot(for: first, policy: disabled, now: now)
        XCTAssertNil(disabledSnapshot)

        try await store.merge(entries: [cacheEntry(2)], for: first, policy: enabled, now: now)
        try await store.merge(entries: [cacheEntry(3)], for: second, policy: enabled, now: now)
        try await store.clear(first)
        let clearedSnapshot = try await store.snapshot(for: first, policy: enabled, now: now)
        let remainingSnapshot = try await store.snapshot(for: second, policy: enabled, now: now)
        XCTAssertNil(clearedSnapshot)
        XCTAssertNotNil(remainingSnapshot)

        try await store.clearAll()
        let overview = try await store.overview(policy: enabled, now: now)
        XCTAssertEqual(overview, .empty)
    }

    private func temporaryFile() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSvnLogCache-\(UUID().uuidString)", isDirectory: true)
        temporaryRoots.append(root)
        return root.appendingPathComponent("log-cache.json")
    }
}

private func cacheEntry(_ revision: Int, message: String = "cached") -> LogEntry {
    LogEntry(
        revision: Revision(revision),
        author: "author",
        date: Date(timeIntervalSince1970: TimeInterval(revision)),
        message: message,
        changedPaths: [
            ChangedPath(
                path: "/file-\(revision)",
                action: .modified,
                kind: "file",
                copyFromPath: nil,
                copyFromRevision: nil
            )
        ]
    )
}
