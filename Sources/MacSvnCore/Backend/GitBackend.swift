import Foundation

public protocol GitBackend: Sendable {
    func initRepository(at repository: URL) async throws
    func addAll(repository: URL) async throws
    func commit(repository: URL, message: String) async throws
}
