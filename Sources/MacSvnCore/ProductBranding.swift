import Foundation

/// 产品对外品牌（与 Swift 模块名 MacSvn* 解耦；彻底换皮只改此处与包装工程）。
public enum ProductBranding: Sendable {
    /// 用户可见名称
    public static let displayName = "SVN Studio"
    /// `.app` / 可执行文件名（无空格）
    public static let appFileName = "SVNStudio"
    /// Bundle ID
    public static let bundleIdentifier = "dev.yclenove.svnstudio"
    /// Finder Sync Bundle ID
    public static let finderSyncBundleIdentifier = "dev.yclenove.svnstudio.FinderSync"
    /// Quick Look Bundle ID
    public static let quickLookBundleIdentifier = "dev.yclenove.svnstudio.QuickLook"
    /// 深链 scheme（不含 ://）
    public static let urlScheme = "svnstudio"
    /// `~/Library/Application Support/<name>/`
    public static let supportDirectoryName = "SVNStudio"
    /// Keychain service
    public static let keychainService = "SVNStudio.AIProvider"
    /// Keychain account / ref 前缀
    public static let keychainRefPrefix = "svnstudio.ai-provider."
    /// 主应用图标资源名（Info.plist、SwiftPM 包装与 Xcode target 共用）。
    public static let iconResourceName = "SVNStudio.icns"
    /// 单例关于窗口的稳定 Scene ID。
    public static let aboutWindowID = "about"
    public static var aboutWindowTitle: String { "关于 \(displayName)" }
    /// About 面板中的项目主页。
    public static let sourceRepositoryURL = URL(
        string: "https://github.com/yclenove/mac-svn-desktop"
    )!

    public static var supportDirectoryURL: URL {
        get throws {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return base.appendingPathComponent(supportDirectoryName, isDirectory: true)
        }
    }
}
