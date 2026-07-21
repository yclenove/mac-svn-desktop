import Foundation

/// Check for Modifications（小乌龟 CFM）列表列标识。
public enum CFMColumnID: String, Codable, CaseIterable, Equatable, Sendable {
    case path
    case textStatus
    case remoteStatus
    case revision
    case treeConflict
    case changelist

    public var displayName: String {
        switch self {
        case .path: return "路径"
        case .textStatus: return "状态"
        case .remoteStatus: return "远端"
        case .revision: return "修订"
        case .treeConflict: return "树冲突"
        case .changelist: return "变更列表"
        }
    }
}

/// CFM 列可见性与顺序（可持久化）。
public struct CFMColumnConfiguration: Codable, Equatable, Sendable {
    /// 有序可见列；`path` 必须始终存在。
    public var visibleOrderedIDs: [CFMColumnID]

    public init(visibleOrderedIDs: [CFMColumnID] = CFMColumnID.allCases) {
        var ids = visibleOrderedIDs
        if !ids.contains(.path) {
            ids.insert(.path, at: 0)
        }
        self.visibleOrderedIDs = ids
    }

    public static let `default` = CFMColumnConfiguration()

    public func isVisible(_ id: CFMColumnID) -> Bool {
        visibleOrderedIDs.contains(id)
    }

    public mutating func setVisible(_ id: CFMColumnID, visible: Bool) {
        if visible {
            guard !visibleOrderedIDs.contains(id) else { return }
            if id == .path {
                visibleOrderedIDs.insert(.path, at: 0)
            } else {
                visibleOrderedIDs.append(id)
            }
        } else {
            // 路径列不可隐藏（否则列表无主键）
            guard id != .path else { return }
            visibleOrderedIDs.removeAll { $0 == id }
        }
    }
}
