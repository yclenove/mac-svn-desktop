import Foundation
import MacSvnCore

/// 应用级依赖注入容器：集中创建并持有 SVN 后端、业务服务与持久化存储。
///
/// 设计意图：
/// - UI 层只依赖本会话，不直接拼装 ProcessRunner / 文件路径；
/// - 支持测试注入自定义 supportDirectory，避免污染真实 Application Support；
/// - svn 可执行路径优先取设置，否则回退 Homebrew / 系统常见路径。
@MainActor
public final class MacSvnAppSession: ObservableObject {
    public let supportDirectory: URL
    public let settingsStore: SettingsStore
    public let workspaceStore: WorkspaceStore
    public let svnService: SvnService
    public let environmentChecker: SvnEnvironmentChecker
    public let svnExecutablePath: String

    public init(
        supportDirectory: URL,
        settingsStore: SettingsStore,
        workspaceStore: WorkspaceStore,
        svnService: SvnService,
        environmentChecker: SvnEnvironmentChecker = SvnEnvironmentChecker(),
        svnExecutablePath: String
    ) {
        self.supportDirectory = supportDirectory
        self.settingsStore = settingsStore
        self.workspaceStore = workspaceStore
        self.svnService = svnService
        self.environmentChecker = environmentChecker
        self.svnExecutablePath = svnExecutablePath
    }

    /// 从 support 目录引导会话：加载设置、创建后端与服务、确保持久化文件存在。
    public static func bootstrap(supportDirectory: URL? = nil) async throws -> MacSvnAppSession {
        let directory = try resolveSupportDirectory(supportDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let settingsStore = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let workspaceStore = WorkspaceStore(fileURL: directory.appendingPathComponent("workspaces.json"))

        let settings = try await settingsStore.load()
        // 首次引导时落盘默认文件，保证 Application Support 目录可观测、可备份
        try await settingsStore.update(settings)
        let workspaces = try await workspaceStore.load()
        // load 已在校验后写回；空列表时再显式 save 一次确保文件存在
        if workspaces.isEmpty {
            _ = try await workspaceStore.load()
        }
        // 通过 PersistenceStore 直接确保 workspaces.json 存在
        try ensureFileExists(
            at: directory.appendingPathComponent("workspaces.json"),
            defaultJSON: #"{"version":1,"workspaces":[]}"#
        )

        let svnPath = resolveSvnExecutablePath(configured: settings.svnPath)
        let backend = SvnCliBackend(
            svnExecutable: svnPath,
            runner: ProcessRunner(),
            timeout: settings.processTimeout
        )
        let svnService = SvnService(backend: backend)

        return MacSvnAppSession(
            supportDirectory: directory,
            settingsStore: settingsStore,
            workspaceStore: workspaceStore,
            svnService: svnService,
            svnExecutablePath: svnPath
        )
    }

    private static func ensureFileExists(at url: URL, defaultJSON: String) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try defaultJSON.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    /// 默认 Application Support 目录：`~/Library/Application Support/MacSVN/`
    public static func defaultSupportDirectory() throws -> URL {
        try resolveSupportDirectory(nil)
    }

    private static func resolveSupportDirectory(_ override: URL?) throws -> URL {
        if let override {
            return override
        }

        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("MacSVN", isDirectory: true)
    }

    /// 解析 svn 可执行路径：用户配置非空时始终优先（即使当前不可执行，交由环境门禁提示）；
    /// 未配置时在常见安装位置中选第一个可执行文件。
    public static func resolveSvnExecutablePath(configured: String?) -> String {
        if let trimmed = configured?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            return trimmed
        }

        let candidates = [
            "/opt/homebrew/bin/svn",
            "/usr/local/bin/svn",
            "/usr/bin/svn"
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        return "/opt/homebrew/bin/svn"
    }
}
