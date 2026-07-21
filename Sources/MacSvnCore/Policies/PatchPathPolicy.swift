import Foundation

public enum PatchPathError: Error, Equatable, Sendable {
    case noSelectedPaths
    case emptyPatch
    case rejectedPaths([String])
}

public enum PatchPathPolicy {
    public static func validate(_ paths: [String]) throws -> [String] {
        let normalized = paths.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !normalized.isEmpty, normalized.allSatisfy({ !$0.isEmpty }) else {
            throw PatchPathError.noSelectedPaths
        }
        return normalized
    }
}
