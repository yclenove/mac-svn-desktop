import Foundation

public protocol GitBackend: Sendable {
    func initRepository(at repository: URL) async throws
    func addAll(repository: URL) async throws
    func commit(repository: URL, message: String) async throws
    func svnClone(
        sourceURL: String,
        destination: URL,
        authorsFile: URL,
        layout: GitMigrationRepositoryLayout,
        revisionRange: RevisionRange?,
        username: String?
    ) async throws
}

public extension GitBackend {
    func svnClone(
        sourceURL: String,
        destination: URL,
        authorsFile: URL,
        layout: GitMigrationRepositoryLayout,
        revisionRange: RevisionRange?,
        username: String?
    ) async throws {
        throw SvnError.other(code: nil, stderr: "git svn clone is unavailable for this backend")
    }
}
