import Foundation

public enum RepoRemoteOperation: Equatable, Sendable {
    case mkdir
    case delete
    case copy
    case move
    case rename
}

public struct RepoRemoteWriteConfirmation: Equatable, Sendable {
    public let operation: RepoRemoteOperation
    public let sourceURL: String
    public let destinationURL: String?

    public init(operation: RepoRemoteOperation, sourceURL: String, destinationURL: String?) {
        self.operation = operation
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
    }
}

public enum RepoRemoteWriteConfirmationPolicy {
    public static func confirmation(
        for operation: RepoRemoteOperation,
        sourceURL: String,
        destinationURL: String? = nil
    ) -> RepoRemoteWriteConfirmation? {
        switch operation {
        case .delete, .move, .rename:
            return RepoRemoteWriteConfirmation(
                operation: operation,
                sourceURL: sourceURL,
                destinationURL: destinationURL
            )
        case .mkdir, .copy:
            return nil
        }
    }
}
