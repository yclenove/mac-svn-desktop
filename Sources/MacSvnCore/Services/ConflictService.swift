import Foundation

public protocol ConflictStatusProviding: Sendable {
    func status(wc: URL) async throws -> [FileStatus]
}

public protocol ConflictInfoProviding: Sendable {
    func info(wc: URL, target: String) async throws -> SvnInfo
}

public protocol ConflictResolving: Sendable {
    func resolve(wc: URL, path: String, accept: ResolveAccept) async throws
}

public protocol ConflictReverting: Sendable {
    func revert(wc: URL, paths: [String], recursive: Bool) async throws
}

public actor ConflictService {
    private let statusProvider: any ConflictStatusProviding
    private let infoProvider: any ConflictInfoProviding
    private let resolveProvider: any ConflictResolving
    private let revertProvider: (any ConflictReverting)?

    public init(
        statusProvider: any ConflictStatusProviding,
        infoProvider: any ConflictInfoProviding,
        resolveProvider: any ConflictResolving,
        revertProvider: (any ConflictReverting)? = nil
    ) {
        self.statusProvider = statusProvider
        self.infoProvider = infoProvider
        self.resolveProvider = resolveProvider
        self.revertProvider = revertProvider ?? (resolveProvider as? any ConflictReverting)
    }

    public func conflicts(wc: URL) async throws -> [ConflictInfo] {
        let statuses = try await statusProvider.status(wc: wc)
        var conflicts: [ConflictInfo] = []

        for status in statuses where status.itemStatus == .conflicted || status.isTreeConflict {
            let info = try await infoProvider.info(wc: wc, target: status.path)
            let statusConflicts = info.conflicts.isEmpty
                ? [fallbackConflict(from: status)]
                : info.conflicts
            conflicts += statusConflicts.map { absolutizedConflict($0, wc: wc) }
        }

        return conflicts
    }

    public func loadTextConflict(_ conflict: ConflictInfo) async throws -> (base: String, mine: String, theirs: String) {
        guard
            let baseFile = conflict.baseFile,
            let mineFile = conflict.mineFile,
            let theirsFile = conflict.theirsFile
        else {
            throw SvnError.parse(detail: "Text conflict is missing base, mine, or theirs file path.")
        }

        return (
            base: try String(contentsOfFile: baseFile, encoding: .utf8),
            mine: try String(contentsOfFile: mineFile, encoding: .utf8),
            theirs: try String(contentsOfFile: theirsFile, encoding: .utf8)
        )
    }

    public func saveResolution(_ conflict: ConflictInfo, wc: URL, mergedText: String) async throws {
        let workingFile = workingFileURL(for: conflict, wc: wc)
        try Data(mergedText.utf8).write(to: workingFile, options: .atomic)
        try await resolveProvider.resolve(wc: wc, path: conflict.path, accept: .working)
    }

    public func resolveWholeFile(_ conflict: ConflictInfo, wc: URL, accept: ResolveAccept) async throws {
        try await resolveProvider.resolve(wc: wc, path: conflict.path, accept: accept)
    }

    public func resolveTreeConflict(_ conflict: ConflictInfo, wc: URL, resolution: TreeConflictResolution) async throws {
        guard conflict.kind == .tree else {
            throw SvnError.parse(detail: "Expected tree conflict for \(conflict.path).")
        }

        try await resolveProvider.resolve(wc: wc, path: conflict.path, accept: .working)

        if resolution == .acceptRemote {
            guard let revertProvider else {
                throw SvnError.parse(detail: "Tree conflict remote resolution requires revert support for \(conflict.path).")
            }

            try await revertProvider.revert(wc: wc, paths: [conflict.path], recursive: false)
        }
    }

    private func fallbackConflict(from status: FileStatus) -> ConflictInfo {
        ConflictInfo(
            path: status.path,
            kind: status.isTreeConflict ? .tree : .unknown,
            baseFile: nil,
            mineFile: nil,
            theirsFile: nil,
            treeConflict: nil
        )
    }

    private func absolutizedConflict(_ conflict: ConflictInfo, wc: URL) -> ConflictInfo {
        ConflictInfo(
            path: conflict.path,
            kind: conflict.kind,
            baseFile: absolutePath(conflict.baseFile, wc: wc),
            mineFile: absolutePath(conflict.mineFile, wc: wc),
            theirsFile: absolutePath(conflict.theirsFile, wc: wc),
            treeConflict: conflict.treeConflict
        )
    }

    private func absolutePath(_ path: String?, wc: URL) -> String? {
        guard let path, !path.isEmpty else {
            return nil
        }

        if path.hasPrefix("/") {
            return path
        }

        return wc.appendingPathComponent(path).path
    }

    private func workingFileURL(for conflict: ConflictInfo, wc: URL) -> URL {
        if conflict.path.hasPrefix("/") {
            return URL(fileURLWithPath: conflict.path)
        }

        return wc.appendingPathComponent(conflict.path)
    }
}

extension SvnService: ConflictStatusProviding {}
extension SvnService: ConflictInfoProviding {}
extension SvnService: ConflictResolving {}
extension SvnService: ConflictReverting {}
