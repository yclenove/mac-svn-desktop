import Foundation
import SwiftUI

/// ST 专业工具面：页面枚举与键盘/a11y 契约（纯策略，无业务状态）。
enum MacSvnSpecializedToolsPage: String, CaseIterable, Sendable {
    case blame
    case aiAssistant
    case gitMigration
    case releaseNotes
}

enum MacSvnSpecializedToolsMetrics {
    static let toolbarHeight: CGFloat = 48
    static let feedbackBarHeight: CGFloat = 30
    static let iconButtonMinSide: CGFloat = 28
}

enum MacSvnSpecializedToolsContract {
    /// 具备显式刷新/重载语义的专业页需要 ⌘R。
    static func requiresRefreshShortcut(for page: MacSvnSpecializedToolsPage) -> Bool {
        switch page {
        case .blame, .aiAssistant, .releaseNotes:
            return true
        case .gitMigration:
            // 迁移向导以分步执行为主，无单一「刷新列表」语义。
            return false
        }
    }

    /// 具备主过滤/搜索框时需要 ⌘F（当前四页默认无独立搜索框）。
    static func requiresSearchFocus(for page: MacSvnSpecializedToolsPage) -> Bool {
        switch page {
        case .blame, .aiAssistant, .gitMigration, .releaseNotes:
            return false
        }
    }

    static func refreshAccessibilityIdentifier(for page: MacSvnSpecializedToolsPage) -> String? {
        guard requiresRefreshShortcut(for: page) else { return nil }
        return "macSvn.st.\(page.rawValue).refresh"
    }

    static func searchAccessibilityIdentifier(for page: MacSvnSpecializedToolsPage) -> String? {
        guard requiresSearchFocus(for: page) else { return nil }
        return "macSvn.st.\(page.rawValue).search"
    }

    /// 独立专业页允许单层 HSplitView；禁止嵌套与 VSplitView。
    static let maxIndependentHSplitViewCount = 1
}
