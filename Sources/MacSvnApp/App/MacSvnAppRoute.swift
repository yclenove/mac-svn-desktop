import Foundation

public enum MacSvnAppSection: String, CaseIterable, Identifiable, Sendable {
    case dailyWork
    case repository
    case conflictResolution
    case advancedSVN
    case automation
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dailyWork:
            "日常工作"
        case .repository:
            "仓库"
        case .conflictResolution:
            "冲突"
        case .advancedSVN:
            "高级 SVN"
        case .automation:
            "自动化"
        case .settings:
            "配置"
        }
    }
}

public enum MacSvnAppRoute: String, CaseIterable, Identifiable, Hashable, Sendable {
    case workspace
    case changes
    case commit
    case diff
    case log
    case repositoryBrowser
    case branches
    case merge
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

    public var commandID: String {
        switch self {
        case .repositoryBrowser:
            "repository-browser"
        case .gitMigration:
            "git-migration"
        case .teamActivity:
            "team-activity"
        case .aiAssistant:
            "ai-assistant"
        case .releaseNotes:
            "release-notes"
        default:
            rawValue
        }
    }

    public var title: String {
        switch self {
        case .workspace:
            "工作副本"
        case .changes:
            "变更"
        case .commit:
            "提交"
        case .diff:
            "Diff"
        case .log:
            "日志"
        case .repositoryBrowser:
            "仓库浏览器"
        case .branches:
            "分支与标签"
        case .merge:
            "冲突合并"
        case .blame:
            "Blame"
        case .properties:
            "属性"
        case .locks:
            "锁定"
        case .shelve:
            "本地搁置"
        case .gitMigration:
            "Git 迁移"
        case .teamActivity:
            "团队动态"
        case .aiAssistant:
            "AI 助手"
        case .releaseNotes:
            "Release Notes"
        case .settings:
            "设置"
        }
    }

    public var subtitle: String {
        switch self {
        case .workspace:
            "工作副本列表"
        case .changes:
            "状态树"
        case .commit:
            "提交队列"
        case .diff:
            "差异预览"
        case .log:
            "提交历史"
        case .repositoryBrowser:
            "远端目录"
        case .branches:
            "分支工作流"
        case .merge:
            "冲突处理"
        case .blame:
            "行级追溯"
        case .properties:
            "SVN 属性"
        case .locks:
            "文件锁"
        case .shelve:
            "本地快照"
        case .gitMigration:
            "迁移向导"
        case .teamActivity:
            "团队概览"
        case .aiAssistant:
            "智能辅助"
        case .releaseNotes:
            "AI 发布说明"
        case .settings:
            "应用配置"
        }
    }

    public var systemImage: String {
        switch self {
        case .workspace:
            "externaldrive"
        case .changes:
            "list.bullet.rectangle"
        case .commit:
            "tray.and.arrow.up"
        case .diff:
            "doc.text.magnifyingglass"
        case .log:
            "clock.arrow.circlepath"
        case .repositoryBrowser:
            "network"
        case .branches:
            "point.topleft.down.curvedto.point.bottomright.up"
        case .merge:
            "arrow.triangle.merge"
        case .blame:
            "person.text.rectangle"
        case .properties:
            "tag"
        case .locks:
            "lock"
        case .shelve:
            "archivebox"
        case .gitMigration:
            "arrow.triangle.branch"
        case .teamActivity:
            "person.3"
        case .aiAssistant:
            "sparkles"
        case .releaseNotes:
            "doc.richtext"
        case .settings:
            "gearshape"
        }
    }

    public var section: MacSvnAppSection {
        switch self {
        case .workspace, .changes, .commit, .diff, .log:
            .dailyWork
        case .repositoryBrowser, .branches:
            .repository
        case .merge:
            .conflictResolution
        case .blame, .properties, .locks, .shelve:
            .advancedSVN
        case .gitMigration, .teamActivity, .aiAssistant, .releaseNotes:
            .automation
        case .settings:
            .settings
        }
    }
}

public struct MacSvnSidebarSection: Equatable, Identifiable, Sendable {
    public var id: MacSvnAppSection { section }
    public let section: MacSvnAppSection
    public let routes: [MacSvnAppRoute]

    public init(section: MacSvnAppSection, routes: [MacSvnAppRoute]) {
        self.section = section
        self.routes = routes
    }
}

public struct MacSvnSidebarModel: Equatable, Sendable {
    public let sections: [MacSvnSidebarSection]
    public let defaultSelection: MacSvnAppRoute

    public init(routes: [MacSvnAppRoute] = MacSvnAppRoute.allCases) {
        sections = MacSvnAppSection.allCases.compactMap { section in
            let sectionRoutes = routes.filter { $0.section == section }
            guard !sectionRoutes.isEmpty else {
                return nil
            }
            return MacSvnSidebarSection(section: section, routes: sectionRoutes)
        }
        defaultSelection = routes.first ?? .workspace
    }
}
