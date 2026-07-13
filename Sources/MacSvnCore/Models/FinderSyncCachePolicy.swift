import Foundation

public enum FinderSyncCacheMode: String, Codable, CaseIterable, Equatable, Sendable {
    case defaultCache = "default"
    case shell
    case none

    public var displayName: String {
        switch self {
        case .defaultCache: return "Default"
        case .shell: return "Shell"
        case .none: return "None"
        }
    }
}

public struct FinderSyncCachePolicy: Equatable, Sendable {
    public let mode: FinderSyncCacheMode

    public init(mode: FinderSyncCacheMode) {
        self.mode = mode
    }

    public var collectsBadges: Bool {
        mode != .none
    }

    public var cacheTTL: TimeInterval {
        switch mode {
        case .defaultCache: return 8
        case .shell: return 2
        case .none: return 0
        }
    }

    public func statusScope(requestedTarget: String) -> String? {
        switch mode {
        case .defaultCache:
            return "."
        case .shell:
            let trimmed = requestedTarget.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "." : trimmed
        case .none:
            return nil
        }
    }
}
