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
    public let commitMessageHistoryStore: CommitMessageHistoryStore
    public let repoBookmarkStore: RepoBookmarkStore
    public let branchListService: BranchListService
    public let conflictService: ConflictService
    public let shelveService: ShelveService
    public let svnService: SvnService
    public let environmentChecker: SvnEnvironmentChecker
    public let svnExecutablePath: String
    public let gitMigrationSourceAnalyzer: GitMigrationSourceAnalyzer
    public let gitMigrationService: GitMigrationService
    public let gitMigrationSyncService: GitMigrationSyncService
    public let menuBarStatusSnapshotter: MenuBarStatusSnapshotter
    public let menuBarPollIntervalMinutes: Int
    public let aiProviderStore: AIProviderStore
    public let aiKeychainStore: AIKeychainStore
    public let llmClient: LLMHTTPClient
    public let aiProviderConnectivityTester: AIProviderConnectivityTester
    public let aiCommitMessageGenerator: AICommitMessageGenerator
    public let aiPreCommitReviewer: AIPreCommitReviewer
    public let aiConflictAssistant: AIConflictAssistant
    public let aiAuthorMappingInferrer: AIAuthorMappingInferrer
    public let aiReleaseNotesGenerator: AIReleaseNotesGenerator
    public let aiToolRegistry: AISVNToolRegistry
    public let aiToolAuditStore: AIToolAuditStore

    public init(
        supportDirectory: URL,
        settingsStore: SettingsStore,
        workspaceStore: WorkspaceStore,
        commitMessageHistoryStore: CommitMessageHistoryStore,
        repoBookmarkStore: RepoBookmarkStore,
        branchListService: BranchListService,
        conflictService: ConflictService,
        shelveService: ShelveService,
        svnService: SvnService,
        environmentChecker: SvnEnvironmentChecker = SvnEnvironmentChecker(),
        svnExecutablePath: String,
        gitMigrationSourceAnalyzer: GitMigrationSourceAnalyzer,
        gitMigrationService: GitMigrationService,
        gitMigrationSyncService: GitMigrationSyncService,
        menuBarStatusSnapshotter: MenuBarStatusSnapshotter,
        menuBarPollIntervalMinutes: Int = 10,
        aiProviderStore: AIProviderStore,
        aiKeychainStore: AIKeychainStore,
        llmClient: LLMHTTPClient,
        aiProviderConnectivityTester: AIProviderConnectivityTester,
        aiCommitMessageGenerator: AICommitMessageGenerator,
        aiPreCommitReviewer: AIPreCommitReviewer,
        aiConflictAssistant: AIConflictAssistant,
        aiAuthorMappingInferrer: AIAuthorMappingInferrer,
        aiReleaseNotesGenerator: AIReleaseNotesGenerator,
        aiToolRegistry: AISVNToolRegistry,
        aiToolAuditStore: AIToolAuditStore
    ) {
        self.supportDirectory = supportDirectory
        self.settingsStore = settingsStore
        self.workspaceStore = workspaceStore
        self.commitMessageHistoryStore = commitMessageHistoryStore
        self.repoBookmarkStore = repoBookmarkStore
        self.branchListService = branchListService
        self.conflictService = conflictService
        self.shelveService = shelveService
        self.svnService = svnService
        self.environmentChecker = environmentChecker
        self.svnExecutablePath = svnExecutablePath
        self.gitMigrationSourceAnalyzer = gitMigrationSourceAnalyzer
        self.gitMigrationService = gitMigrationService
        self.gitMigrationSyncService = gitMigrationSyncService
        self.menuBarStatusSnapshotter = menuBarStatusSnapshotter
        self.menuBarPollIntervalMinutes = menuBarPollIntervalMinutes
        self.aiProviderStore = aiProviderStore
        self.aiKeychainStore = aiKeychainStore
        self.llmClient = llmClient
        self.aiProviderConnectivityTester = aiProviderConnectivityTester
        self.aiCommitMessageGenerator = aiCommitMessageGenerator
        self.aiPreCommitReviewer = aiPreCommitReviewer
        self.aiConflictAssistant = aiConflictAssistant
        self.aiAuthorMappingInferrer = aiAuthorMappingInferrer
        self.aiReleaseNotesGenerator = aiReleaseNotesGenerator
        self.aiToolRegistry = aiToolRegistry
        self.aiToolAuditStore = aiToolAuditStore
    }

    /// 当前设置中的 AI 隐私策略（供提交/冲突 AI 调用读取）。
    public func currentAIPrivacy() async -> AIPrivacySettings {
        await settingsStore.settings().aiPrivacy
    }

    /// 从 support 目录引导会话：加载设置、创建后端与服务、确保持久化文件存在。
    public static func bootstrap(supportDirectory: URL? = nil) async throws -> MacSvnAppSession {
        let directory = try resolveSupportDirectory(supportDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let settingsStore = SettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let workspaceStore = WorkspaceStore(fileURL: directory.appendingPathComponent("workspaces.json"))
        let commitMessageHistoryStore = CommitMessageHistoryStore(
            fileURL: directory.appendingPathComponent("commit-history.json")
        )
        let repoBookmarkStore = RepoBookmarkStore(
            fileURL: directory.appendingPathComponent("bookmarks.json")
        )

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
        var guardConfig = CommitGuardConfiguration()
        if settings.commitGuardHardBlockConflictMarkers {
            guardConfig.hardBlockedRules.insert(.conflictMarker)
        }
        let svnService = SvnService(
            backend: backend,
            credentialProvider: MacSvnInteractiveCredentialProvider(),
            commitGuard: CommitGuardService(configuration: guardConfig)
        )
        let branchListService = BranchListService(listProvider: svnService)
        let conflictService = ConflictService(
            statusProvider: svnService,
            infoProvider: svnService,
            resolveProvider: svnService,
            revertProvider: svnService
        )
        let shelveRoot = directory.appendingPathComponent("shelves", isDirectory: true)
        try FileManager.default.createDirectory(at: shelveRoot, withIntermediateDirectories: true)
        let shelveService = ShelveService(
            store: ShelveStore(rootDirectory: shelveRoot),
            svn: svnService
        )

        let processRunner = ProcessRunner()
        let gitEnvironmentChecker = GitMigrationEnvironmentChecker(
            runner: processRunner,
            timeout: settings.processTimeout
        )
        let gitMigrationSourceAnalyzer = GitMigrationSourceAnalyzer(
            environmentChecker: gitEnvironmentChecker,
            listProvider: svnService,
            logProvider: svnService
        )
        let gitBackend = GitCliBackend(
            runner: processRunner,
            timeout: settings.processTimeout
        )
        let gitMigrationService = GitMigrationService(
            svnExporter: svnService,
            gitBackend: gitBackend
        )
        let gitMigrationSyncService = GitMigrationSyncService(
            store: GitMigrationSyncStore(
                fileURL: directory.appendingPathComponent("git-migrations.json")
            ),
            gitBackend: gitBackend
        )
        let menuBarConfiguration = MenuBarMonitorConfiguration()
        let menuBarStatusSnapshotter = MenuBarStatusSnapshotter(
            statusProvider: svnService,
            remoteLogProvider: svnService,
            configuration: menuBarConfiguration
        )

        let aiProviderStore = AIProviderStore(
            fileURL: directory.appendingPathComponent("ai-providers.json")
        )
        let aiKeychainStore = AIKeychainStore()
        let llmClient = LLMHTTPClient(apiKeyStore: aiKeychainStore)
        let aiProviderConnectivityTester = AIProviderConnectivityTester(llmClient: llmClient)
        let aiCommitMessageGenerator = AICommitMessageGenerator(
            providerManager: aiProviderStore,
            diffProvider: svnService,
            llmClient: llmClient
        )
        let aiPreCommitReviewer = AIPreCommitReviewer(
            providerManager: aiProviderStore,
            diffProvider: svnService,
            llmClient: llmClient
        )
        let aiConflictAssistant = AIConflictAssistant(
            providerManager: aiProviderStore,
            llmClient: llmClient
        )
        let aiAuthorMappingInferrer = AIAuthorMappingInferrer(
            providerManager: aiProviderStore,
            llmClient: llmClient
        )
        let aiReleaseNotesGenerator = AIReleaseNotesGenerator(
            providerManager: aiProviderStore,
            llmClient: llmClient
        )
        let aiToolAuditStore = AIToolAuditStore(
            fileURL: directory.appendingPathComponent("ai-tool-audit.json")
        )
        let aiToolRegistry = AISVNToolRegistry(
            service: svnService,
            auditStore: aiToolAuditStore
        )

        return MacSvnAppSession(
            supportDirectory: directory,
            settingsStore: settingsStore,
            workspaceStore: workspaceStore,
            commitMessageHistoryStore: commitMessageHistoryStore,
            repoBookmarkStore: repoBookmarkStore,
            branchListService: branchListService,
            conflictService: conflictService,
            shelveService: shelveService,
            svnService: svnService,
            svnExecutablePath: svnPath,
            gitMigrationSourceAnalyzer: gitMigrationSourceAnalyzer,
            gitMigrationService: gitMigrationService,
            gitMigrationSyncService: gitMigrationSyncService,
            menuBarStatusSnapshotter: menuBarStatusSnapshotter,
            menuBarPollIntervalMinutes: menuBarConfiguration.pollIntervalMinutes,
            aiProviderStore: aiProviderStore,
            aiKeychainStore: aiKeychainStore,
            llmClient: llmClient,
            aiProviderConnectivityTester: aiProviderConnectivityTester,
            aiCommitMessageGenerator: aiCommitMessageGenerator,
            aiPreCommitReviewer: aiPreCommitReviewer,
            aiConflictAssistant: aiConflictAssistant,
            aiAuthorMappingInferrer: aiAuthorMappingInferrer,
            aiReleaseNotesGenerator: aiReleaseNotesGenerator,
            aiToolRegistry: aiToolRegistry,
            aiToolAuditStore: aiToolAuditStore
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
