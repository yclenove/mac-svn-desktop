import Foundation

public enum ShelveServiceError: Error, Equatable, Sendable {
    case emptyPatch
    case noSelectedPaths
    case officialUnavailable
    case cannotMigrateSafetySnapshot
}

public protocol ShelveSvnProviding: Sendable {
    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String
    func revert(wc: URL, paths: [String], recursive: Bool) async throws
    func applyPatch(wc: URL, patchFile: URL) async throws
}

public struct ShelveService: Sendable {
    private let store: ShelveStore
    private let svn: any ShelveSvnProviding
    private let official: (any SvnExperimentalShelvingProviding)?

    public init(store: ShelveStore, svn: any ShelveSvnProviding) {
        self.init(store: store, svn: svn, official: nil)
    }

    public init(
        store: ShelveStore,
        svn: any ShelveSvnProviding,
        official: (any SvnExperimentalShelvingProviding)?
    ) {
        self.store = store
        self.svn = svn
        self.official = official
    }

    public func load() async throws -> [ShelveSnapshot] {
        try await store.load()
    }

    public func shelve(wc: URL, name: String, paths: [String]) async throws -> ShelveSnapshot {
        let snapshot = try await createSnapshot(wc: wc, name: name, paths: paths, kind: .manual)
        try await svn.revert(wc: wc, paths: paths, recursive: true)
        return snapshot
    }

    public func createSafetySnapshot(wc: URL, name: String, paths: [String]) async throws -> ShelveSnapshot {
        try await createSnapshot(wc: wc, name: name, paths: paths, kind: .safety)
    }

    public func restore(_ snapshot: ShelveSnapshot, deleteAfterRestore: Bool = true) async throws {
        let patchFile = await store.patchFileURL(for: snapshot)
        try await svn.applyPatch(wc: URL(fileURLWithPath: snapshot.wcPath), patchFile: patchFile)

        if deleteAfterRestore {
            try await store.delete(snapshot)
        }
    }

    public func delete(_ snapshot: ShelveSnapshot) async throws {
        try await store.delete(snapshot)
    }

    public func preview(_ snapshot: ShelveSnapshot) async throws -> String {
        try await store.preview(snapshot)
    }

    public func officialAvailability(wc: URL) async -> SvnShelvingAvailability {
        guard let official else {
            return .unavailable(.v3, reason: "official shelving provider is not configured")
        }
        return await official.availability(wc: wc)
    }

    public func officialShelves(wc: URL) async throws -> [SvnShelf] {
        try await officialProvider().list(wc: wc)
    }

    public func officialShelve(
        wc: URL,
        name: String,
        paths: [String],
        message: String,
        keepLocal: Bool
    ) async throws {
        try await officialProvider().shelve(
            wc: wc,
            name: name,
            paths: paths,
            message: message,
            keepLocal: keepLocal
        )
    }

    public func officialDiff(wc: URL, name: String, version: Int?) async throws -> String {
        try await officialProvider().diff(wc: wc, name: name, version: version)
    }

    public func officialLog(wc: URL, name: String) async throws -> String {
        try await officialProvider().log(wc: wc, name: name)
    }

    public func officialUnshelve(wc: URL, name: String, version: Int?, drop: Bool) async throws {
        try await officialProvider().unshelve(wc: wc, name: name, version: version, drop: drop)
    }

    public func officialDrop(wc: URL, name: String) async throws {
        try await officialProvider().drop(wc: wc, name: name)
    }

    /// 将仍由本地 patch 管理的手工快照迁移为 SVN 官方 shelf。
    /// 官方命令成功前不删除本地快照，避免迁移失败造成不可恢复的数据损失。
    public func migrateToOfficial(_ snapshot: ShelveSnapshot) async throws {
        guard snapshot.kind == .manual else {
            throw ShelveServiceError.cannotMigrateSafetySnapshot
        }

        try await restore(snapshot, deleteAfterRestore: false)
        try await officialProvider().shelve(
            wc: URL(fileURLWithPath: snapshot.wcPath),
            name: snapshot.name,
            paths: snapshot.paths,
            message: snapshot.name,
            keepLocal: false
        )
        try await store.delete(snapshot)
    }

    private func officialProvider() throws -> any SvnExperimentalShelvingProviding {
        guard let official else {
            throw ShelveServiceError.officialUnavailable
        }
        return official
    }

    private func createSnapshot(wc: URL, name: String, paths: [String], kind: ShelveKind) async throws -> ShelveSnapshot {
        guard !paths.isEmpty else {
            throw ShelveServiceError.noSelectedPaths
        }

        let patchText = try await patchText(wc: wc, paths: paths)
        guard !patchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ShelveServiceError.emptyPatch
        }

        return try await store.createSnapshot(
            wc: wc,
            name: name,
            paths: paths,
            patchText: patchText,
            kind: kind
        )
    }

    private func patchText(wc: URL, paths: [String]) async throws -> String {
        var diffs: [String] = []

        for path in paths {
            let diff = try await svn.diff(wc: wc, target: path, r1: nil, r2: nil)
            if !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diffs.append(diff)
            }
        }

        return diffs.joined(separator: "\n")
    }
}

extension SvnService: ShelveSvnProviding {}
