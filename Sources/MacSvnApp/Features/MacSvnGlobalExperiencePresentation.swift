import Foundation
import SwiftUI

/// U8 全局体验：页面级键盘与无障碍契约（纯策略，无业务状态）。
enum MacSvnGlobalKeyboardPage: String, CaseIterable, Sendable {
    case changes
    case log
    case repoBrowser
    case branches
    case conflicts
    case diff
    case commit
    case properties
    case locks
    case shelve
    case settings
    /// 对照页：无刷新语义，不要求 ⌘R。
    case about
}

enum MacSvnGlobalKeyboardContract {
    /// 具备主搜索/过滤框的页面需要 ⌘F 聚焦。
    static func requiresSearchFocus(for page: MacSvnGlobalKeyboardPage) -> Bool {
        switch page {
        case .changes, .log, .properties, .locks, .shelve, .settings:
            return true
        case .repoBrowser, .branches, .conflicts, .diff, .commit, .about:
            return false
        }
    }

    /// 具备工具栏刷新语义的页面需要 ⌘R。
    static func requiresRefreshShortcut(for page: MacSvnGlobalKeyboardPage) -> Bool {
        switch page {
        case .about:
            return false
        case .changes, .log, .repoBrowser, .branches, .conflicts, .diff, .commit,
             .properties, .locks, .shelve, .settings:
            return true
        }
    }

    static func searchAccessibilityIdentifier(for page: MacSvnGlobalKeyboardPage) -> String? {
        guard requiresSearchFocus(for: page) else { return nil }
        return "macSvn.\(page.rawValue).search"
    }

    static func refreshAccessibilityIdentifier(for page: MacSvnGlobalKeyboardPage) -> String? {
        guard requiresRefreshShortcut(for: page) else { return nil }
        return "macSvn.\(page.rawValue).refresh"
    }
}

/// Reduce Motion 统一策略：override 优先于系统 accessibilityReduceMotion。
enum MacSvnMotionPolicy {
    static func shouldAnimate(
        accessibilityReduceMotion: Bool,
        override: Bool?
    ) -> Bool {
        let reduce = override ?? accessibilityReduceMotion
        return !reduce
    }

    static func run(
        accessibilityReduceMotion: Bool,
        override: Bool?,
        animation: Animation = .easeInOut(duration: 0.18),
        _ body: () -> Void
    ) {
        if shouldAnimate(accessibilityReduceMotion: accessibilityReduceMotion, override: override) {
            withAnimation(animation, body)
        } else {
            body()
        }
    }
}


/// 嵌入工作区时不注册 ⌘R，避免与变更页主刷新冲突；独立页启用。
struct MacSvnCommandRShortcutModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.keyboardShortcut("r", modifiers: .command)
        } else {
            content
        }
    }
}
