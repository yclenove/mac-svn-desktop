import Foundation

public protocol SvnBackend: Sendable {
    func version() async throws -> SvnVersion
    func status(wc: URL) async throws -> [FileStatus]
    func update(wc: URL, paths: [String], revision: Revision?, auth: Credential?) async throws -> UpdateSummary
    func commit(wc: URL, paths: [String], message: String, auth: Credential?) async throws -> Revision
    func add(wc: URL, paths: [String]) async throws
    func delete(wc: URL, paths: [String]) async throws
    func revert(wc: URL, paths: [String], recursive: Bool) async throws
    func cleanup(wc: URL) async throws
    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String
    func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry]
    func checkout(url: String, to destination: URL, depth: SvnDepth, auth: Credential?) async throws
    func info(wc: URL, target: String) async throws -> SvnInfo
}
