import Foundation

public protocol SvnBackend: Sendable {
    func version() async throws -> SvnVersion
    func status(wc: URL) async throws -> [FileStatus]
    func update(wc: URL, paths: [String], revision: Revision?) async throws -> UpdateSummary
    func commit(wc: URL, paths: [String], message: String, auth: Credential?) async throws -> Revision
}
