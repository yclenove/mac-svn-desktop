import Foundation

public enum VersionControlRemovalError: Error, Equatable, Sendable {
    case emptyPath
    case filesystemRoot
    case metadataDirectory
}

public enum VersionControlRemovalPolicy {
    public static func validate(_ path: URL) throws {
        let normalized = path.standardizedFileURL.path
        guard !normalized.isEmpty else { throw VersionControlRemovalError.emptyPath }
        guard normalized != "/" else { throw VersionControlRemovalError.filesystemRoot }
        guard path.lastPathComponent != ".svn" else {
            throw VersionControlRemovalError.metadataDirectory
        }
    }
}
