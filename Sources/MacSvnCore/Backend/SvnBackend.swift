import Foundation

public protocol SvnBackend: Sendable {
    func version() async throws -> SvnVersion
    func status(wc: URL) async throws -> [FileStatus]
    func update(wc: URL, paths: [String], revision: Revision?, setDepth: SvnDepth?, auth: Credential?) async throws -> UpdateSummary
    func switchTo(wc: URL, url: String, auth: Credential?) async throws -> UpdateSummary
    func merge(wc: URL, source: String, range: RevisionRange?, dryRun: Bool, auth: Credential?) async throws -> MergeSummary
    func commit(wc: URL, paths: [String], message: String, auth: Credential?) async throws -> Revision
    func add(wc: URL, paths: [String]) async throws
    func delete(wc: URL, paths: [String]) async throws
    func revert(wc: URL, paths: [String], recursive: Bool) async throws
    func cleanup(wc: URL) async throws
    func resolve(wc: URL, path: String, accept: ResolveAccept) async throws
    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String
    func applyPatch(wc: URL, patchFile: URL) async throws
    func blame(wc: URL, target: String) async throws -> [BlameLine]
    func properties(wc: URL, target: String) async throws -> [SvnProperty]
    func propertyValue(wc: URL, target: String, name: String) async throws -> SvnProperty?
    func setProperty(wc: URL, target: String, name: String, value: String) async throws
    func deleteProperty(wc: URL, target: String, name: String) async throws
    func locks(wc: URL, targets: [String]) async throws -> [SvnLock]
    func lock(wc: URL, paths: [String], message: String?, force: Bool) async throws
    func unlock(wc: URL, paths: [String], force: Bool) async throws
    func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry]
    func remoteLog(url: String, from: Revision, batch: Int, verbose: Bool, auth: Credential?) async throws -> [LogEntry]
    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry]
    func cat(url: String, revision: Revision?, sizeLimit: Int, auth: Credential?) async throws -> Data
    func checkout(url: String, to destination: URL, depth: SvnDepth, auth: Credential?) async throws
    func copy(source: String, destination: String, message: String, auth: Credential?) async throws -> Revision
    func info(wc: URL, target: String) async throws -> SvnInfo
}
