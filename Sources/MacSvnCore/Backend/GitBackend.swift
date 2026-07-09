import Foundation

public protocol GitBackend: Sendable {
    func initRepository(at repository: URL) async throws
    func addAll(repository: URL) async throws
    func commit(repository: URL, message: String) async throws
    func gitSvnRevisions(repository: URL) async throws -> [GitSvnRevisionMetadata]
    func svnFetch(repository: URL) async throws
    func pushAll(repository: URL, remote: String) async throws
    func pushTags(repository: URL, remote: String) async throws
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
    func gitSvnRevisions(repository: URL) async throws -> [GitSvnRevisionMetadata] {
        throw SvnError.other(code: nil, stderr: "git svn revision metadata is unavailable for this backend")
    }

    func svnFetch(repository: URL) async throws {
        throw SvnError.other(code: nil, stderr: "git svn fetch is unavailable for this backend")
    }

    func pushAll(repository: URL, remote: String) async throws {
        throw SvnError.other(code: nil, stderr: "git push is unavailable for this backend")
    }

    func pushTags(repository: URL, remote: String) async throws {
        throw SvnError.other(code: nil, stderr: "git push is unavailable for this backend")
    }

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
