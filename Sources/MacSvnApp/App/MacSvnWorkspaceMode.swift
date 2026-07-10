import Foundation

/// 工作区内模式：侧栏选 WC 后，主区按 Mode 切换能力（Working-Copy Centric）。
public enum MacSvnWorkspaceMode: String, CaseIterable, Identifiable, Hashable, Sendable {
    case changes
    case history
    case browser
    case branches
    case conflicts
    case blame
    case properties
    case locks
    case shelve
    case gitMigration
    case teamActivity
    case aiAssistant
    case releaseNotes
    case settings

    public var id: String { rawValue }

    /// 顶栏主 Tab（日常路径）。
    public static let primaryModes: [MacSvnWorkspaceMode] = [
        .changes, .history, .browser, .branches, .conflicts
    ]

    /// 「更多」溢出（高级 SVN）。
    public static let advancedModes: [MacSvnWorkspaceMode] = [
        .blame, .properties, .locks, .shelve
    ]

    /// 「工具」菜单（附加能力 + 设置）。
    public static let toolModes: [MacSvnWorkspaceMode] = [
        .gitMigration, .teamActivity, .aiAssistant, .releaseNotes, .settings
    ]

    public var title: String {
        switch self {
        case .changes: "变更"
        case .history: "历史"
        case .browser: "浏览"
        case .branches: "分支"
        case .conflicts: "冲突"
        case .blame: "Blame"
        case .properties: "属性"
        case .locks: "锁定"
        case .shelve: "搁置"
        case .gitMigration: "Git 迁移"
        case .teamActivity: "团队动态"
        case .aiAssistant: "AI 助手"
        case .releaseNotes: "Release Notes"
        case .settings: "设置"
        }
    }

    public var systemImage: String {
        switch self {
        case .changes: "list.bullet.rectangle"
        case .history: "clock.arrow.circlepath"
        case .browser: "network"
        case .branches: "point.topleft.down.curvedto.point.bottomright.up"
        case .conflicts: "arrow.triangle.merge"
        case .blame: "person.text.rectangle"
        case .properties: "tag"
        case .locks: "lock"
        case .shelve: "archivebox"
        case .gitMigration: "arrow.triangle.branch"
        case .teamActivity: "person.3"
        case .aiAssistant: "sparkles"
        case .releaseNotes: "doc.richtext"
        case .settings: "gearshape"
        }
    }

    /// 从遗留路由映射到 Mode（commit/diff/workspace 均归入变更工作区）。
    public init(route: MacSvnAppRoute) {
        switch route {
        case .workspace, .changes, .commit, .diff:
            self = .changes
        case .log:
            self = .history
        case .repositoryBrowser:
            self = .browser
        case .branches:
            self = .branches
        case .merge:
            self = .conflicts
        case .blame:
            self = .blame
        case .properties:
            self = .properties
        case .locks:
            self = .locks
        case .shelve:
            self = .shelve
        case .gitMigration:
            self = .gitMigration
        case .teamActivity:
            self = .teamActivity
        case .aiAssistant:
            self = .aiAssistant
        case .releaseNotes:
            self = .releaseNotes
        case .settings:
            self = .settings
        }
    }

    /// Mode 对应的主路由（用于 FeatureHost / 深链兼容）。
    public var primaryRoute: MacSvnAppRoute {
        switch self {
        case .changes: .changes
        case .history: .log
        case .browser: .repositoryBrowser
        case .branches: .branches
        case .conflicts: .merge
        case .blame: .blame
        case .properties: .properties
        case .locks: .locks
        case .shelve: .shelve
        case .gitMigration: .gitMigration
        case .teamActivity: .teamActivity
        case .aiAssistant: .aiAssistant
        case .releaseNotes: .releaseNotes
        case .settings: .settings
        }
    }
}
