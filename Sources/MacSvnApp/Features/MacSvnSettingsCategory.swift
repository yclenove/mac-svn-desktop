import Foundation
import MacSvnCore

public enum MacSvnSettingsCategory: String, CaseIterable, Identifiable, Sendable {
    case general
    case dialogs
    case colours
    case network
    case externalPrograms
    case savedData
    case finder
    case revisionGraph
    case ai

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "General"
        case .dialogs: "Dialogs"
        case .colours: "Colours"
        case .network: "Network"
        case .externalPrograms: "External Programs"
        case .savedData: "Saved Data"
        case .finder: "Finder"
        case .revisionGraph: "Revision Graph"
        case .ai: "AI"
        }
    }

    public var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .dialogs: "rectangle.on.rectangle"
        case .colours: "paintpalette"
        case .network: "network"
        case .externalPrograms: "terminal"
        case .savedData: "externaldrive"
        case .finder: "folder"
        case .revisionGraph: "point.3.connected.trianglepath.dotted"
        case .ai: "sparkles"
        }
    }

    public var searchKeywords: [String] {
        switch self {
        case .general:
            [
                "常规", "通用", "应用", "语言", "更新", "svn", "subversion", "路径",
                "global ignore", "忽略", "提交时间", "externals", "分支布局",
                "trunk", "branches", "tags",
            ]
        case .dialogs:
            [
                "对话框", "日志", "字体", "日期", "还原", "废纸篓", "checkout",
                "未版本", "递归", "自动完成", "提交历史", "锁定", "预取", "externals",
            ]
        case .colours:
            [
                "colors", "colour", "color", "颜色", "状态色", "亮色", "暗色",
                "modified", "added", "deleted", "merged", "conflicted",
            ]
        case .network:
            [
                "网络", "代理", "proxy", "http", "ssh", "server", "服务器",
                "认证", "username", "password", "密码",
            ]
        case .externalPrograms:
            [
                "外置程序", "外部程序", "diff", "merge", "blame", "比较工具",
                "合并工具", "追溯工具", "扩展名", "executable",
            ]
        case .savedData:
            [
                "已保存数据", "保存数据", "cache", "缓存", "auth", "authentication",
                "认证", "hook", "hooks", "钩子", "日志缓存",
            ]
        case .finder:
            [
                "扩展", "菜单", "角标", "badge", "overlay", "缓存", "路径",
                "context menu",
            ]
        case .revisionGraph:
            [
                "修订图", "分支图", "branch graph", "拓扑", "timeline", "trunk",
                "branch", "tag", "复制颜色",
            ]
        case .ai:
            [
                "人工智能", "provider", "模型", "model", "privacy", "隐私",
                "keychain", "连通性", "api key",
            ]
        }
    }

    public func matches(search: String) -> Bool {
        let queryTerms = Self.normalized(search).split(separator: " ")
        guard !queryTerms.isEmpty else { return true }
        let searchableText = Self.normalized(
            ([title, rawValue] + searchKeywords).joined(separator: " ")
        )
        return queryTerms.allSatisfy { searchableText.contains($0) }
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }
}

enum MacSvnSettingsErrorPresentation {
    static func category(for error: Error) -> MacSvnSettingsCategory? {
        guard let configurationError = error as? SvnClientConfigurationError else {
            return nil
        }
        switch configurationError {
        case .invalidValue(let key):
            if ["global-ignores", "use-commit-times"].contains(key) {
                return .general
            }
            if key.hasPrefix("http-") || key == "ssh" {
                return .network
            }
            return nil
        case .invalidProxyPort:
            return .network
        }
    }
}
