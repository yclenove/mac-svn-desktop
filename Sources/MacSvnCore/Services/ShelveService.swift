import Foundation

public enum ShelveServiceError: Error, Equatable, Sendable {
    case emptyPatch
    case noSelectedPaths
}

public protocol ShelveSvnProviding: Sendable {
    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String
    func revert(wc: URL, paths: [String], recursive: Bool) async throws
    func applyPatch(wc: URL, patchFile: URL) async throws
}

public struct ShelveService: Sendable {
    private let store: ShelveStore
    private let svn: any ShelveSvnProviding

    public init(store: ShelveStore, svn: any ShelveSvnProviding) {
        self.store = store
        self.svn = svn
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
