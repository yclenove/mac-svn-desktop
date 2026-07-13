import Foundation

public protocol SvnBackend: Sendable {
    func version() async throws -> SvnVersion
    func status(wc: URL) async throws -> [FileStatus]
    /// Check for Modifications → Check Repository（`svn status -u`）
    func statusAgainstRepository(wc: URL) async throws -> [FileStatus]
    func update(wc: URL, paths: [String], revision: Revision?, setDepth: SvnDepth?, ignoreExternals: Bool, auth: Credential?) async throws -> UpdateSummary
    func switchTo(wc: URL, url: String, revision: Revision?, auth: Credential?) async throws -> UpdateSummary
    func merge(wc: URL, source: String, range: RevisionRange?, dryRun: Bool, auth: Credential?) async throws -> MergeSummary
    func mergeTwoTrees(wc: URL, from: String, to: String, dryRun: Bool, auth: Credential?) async throws -> MergeSummary
    func commit(wc: URL, paths: [String], message: String, auth: Credential?, keepLocks: Bool) async throws -> Revision
    func add(wc: URL, paths: [String]) async throws
    func delete(wc: URL, paths: [String]) async throws
    /// CFM Repair Move：`svn move`（工作副本内，不提交）
    func moveInWorkingCopy(wc: URL, source: String, destination: String) async throws
    /// 同目录 Rename：`svn rename`（工作副本内，不提交）
    func renameInWorkingCopy(wc: URL, source: String, destination: String) async throws
    /// CFM Repair Copy：`svn copy`（工作副本内，不提交）
    func copyInWorkingCopy(wc: URL, source: String, destination: String) async throws
    /// #46：大小写不敏感文件系统上的 case-only rename。
    func repairFilenameCaseConflict(wc: URL, source: String, destination: String) async throws
    func revert(wc: URL, paths: [String], recursive: Bool) async throws
    func cleanup(wc: URL, options: SvnCleanupOptions) async throws
    func resolve(wc: URL, path: String, accept: ResolveAccept) async throws
    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String
    func diffWithURL(
        wc: URL,
        target: String,
        url: String,
        revision: Revision?,
        auth: Credential?
    ) async throws -> String
    /// 双路径 Diff（`--old` / `--new`）
    func diffBetweenPaths(wc: URL, oldPath: String, newPath: String) async throws -> String
    /// 显式对比 BASE
    func diffAgainstBase(wc: URL, target: String) async throws -> String
    func applyPatch(wc: URL, patchFile: URL) async throws
    func blame(wc: URL, target: String) async throws -> [BlameLine]
    func blame(wc: URL, target: String, startRevision: Revision?, endRevision: Revision?) async throws -> [BlameLine]
    func properties(wc: URL, target: String) async throws -> [SvnProperty]
    func propertyValue(wc: URL, target: String, name: String) async throws -> SvnProperty?
    func setProperty(wc: URL, target: String, name: String, value: String) async throws
    func deleteProperty(wc: URL, target: String, name: String) async throws
    func locks(wc: URL, targets: [String]) async throws -> [SvnLock]
    func lock(wc: URL, paths: [String], message: String?, force: Bool) async throws
    func unlock(wc: URL, paths: [String], force: Bool) async throws
    func log(
        wc: URL,
        target: String,
        from: Revision,
        batch: Int,
        verbose: Bool,
        stopOnCopy: Bool
    ) async throws -> [LogEntry]
    func remoteLog(url: String, from: Revision, batch: Int, verbose: Bool, auth: Credential?) async throws -> [LogEntry]
    func remoteLogFromHead(url: String, batch: Int, verbose: Bool, auth: Credential?) async throws -> [LogEntry]
    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry]
    func listWithLocks(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry]
    func cat(url: String, revision: Revision?, sizeLimit: Int, auth: Credential?) async throws -> Data
    func checkout(url: String, to destination: URL, depth: SvnDepth, revision: Revision?, ignoreExternals: Bool, auth: Credential?) async throws
    func export(url: String, to destination: URL, revision: Revision?, ignoreExternals: Bool, auth: Credential?) async throws
    func importProject(path: URL, url: String, message: String, auth: Credential?) async throws -> Revision
    func relocate(wc: URL, from: String, to: String, auth: Credential?) async throws
    func removeFromVersionControl(path: URL, recursive: Bool) async throws
    func copy(source: String, destination: String, message: String, auth: Credential?) async throws -> Revision
    func mkdir(url: String, message: String, auth: Credential?) async throws -> Revision
    func delete(url: String, message: String, auth: Credential?) async throws -> Revision
    func move(source: String, destination: String, message: String, auth: Credential?) async throws -> Revision
    func info(wc: URL, target: String) async throws -> SvnInfo
    /// 查询仓库 HEAD 修订号（`svn info -r HEAD`），供多路径统一更新钉住 revision。
    func repositoryHeadRevision(wc: URL, target: String) async throws -> Revision
}

public extension SvnBackend {
    func diffWithURL(
        wc: URL,
        target: String,
        url: String,
        revision: Revision?,
        auth: Credential?
    ) async throws -> String {
        throw SvnError.other(code: nil, stderr: "diffWithURLUnavailable")
    }

    func listWithLocks(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry] {
        try await list(url: url, depth: depth, auth: auth)
    }

    func blame(
        wc: URL,
        target: String,
        startRevision: Revision?,
        endRevision: Revision?
    ) async throws -> [BlameLine] {
        try await blame(wc: wc, target: target)
    }
}
