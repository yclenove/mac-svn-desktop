import Foundation
import Observation

public protocol TreeConflictResolving: Sendable {
    func resolveTreeConflict(_ conflict: ConflictInfo, wc: URL, resolution: TreeConflictResolution) async throws
}

public enum TreeConflictViewState: Equatable, Sendable {
    case idle
    case resolving
    case resolved(TreeConflictResolution)
    case error(String)
}

@MainActor
@Observable
public final class TreeConflictViewModel {
    private let conflict: ConflictInfo
    private let workingCopy: URL
    private let resolver: any TreeConflictResolving

    public private(set) var state: TreeConflictViewState = .idle

    public init(conflict: ConflictInfo, workingCopy: URL, resolver: any TreeConflictResolving) {
        self.conflict = conflict
        self.workingCopy = workingCopy
        self.resolver = resolver
    }

    public var path: String {
        conflict.path
    }

    public var operation: String? {
        conflict.treeConflict?.operation
    }

    public var action: String? {
        conflict.treeConflict?.action
    }

    public var reason: String? {
        conflict.treeConflict?.reason
    }

    public func resolve(_ resolution: TreeConflictResolution) async {
        state = .resolving

        do {
            try await resolver.resolveTreeConflict(conflict, wc: workingCopy, resolution: resolution)
            state = .resolved(resolution)
        } catch {
            state = .error(String(describing: error))
        }
    }
}

extension ConflictService: TreeConflictResolving {}
