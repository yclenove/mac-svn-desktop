import Foundation

public protocol SvnAuthenticationCacheClearing: Sendable {
    func clearAll() async throws -> SvnAuthenticationCacheClearResult
}

public enum SvnAuthenticationCacheError: Error, Equatable, Sendable {
    case authenticationPathIsNotDirectory(URL)
    case commandFailed(exitCode: Int32, stderr: String)
}

public struct SvnAuthenticationCacheClearResult: Equatable, Sendable {
    public let authenticationDirectory: URL
    public let removedFileCacheItemCount: Int

    public init(authenticationDirectory: URL, removedFileCacheItemCount: Int) {
        self.authenticationDirectory = authenticationDirectory
        self.removedFileCacheItemCount = removedFileCacheItemCount
    }
}

extension SvnAuthenticationCacheError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .authenticationPathIsNotDirectory(let url):
            return "Subversion 认证缓存路径不是目录：\(url.path)"
        case .commandFailed(let exitCode, let stderr):
            return "svn auth 清理失败（退出码 \(exitCode)）：\(stderr)"
        }
    }
}

/// 通过 Subversion 官方命令同时清理 auth 文件和客户端管理的 Keychain 凭据，不触碰应用自己的 Keychain。
public actor SvnAuthenticationCacheStore: SvnAuthenticationCacheClearing {
    private let configurationDirectory: URL
    private let fileManager: FileManager
    private let svnExecutable: String
    private let runner: any ProcessRunning
    private let timeout: TimeInterval

    public init(
        configurationDirectory: URL? = nil,
        svnExecutable: String = "/usr/bin/svn",
        runner: any ProcessRunning = ProcessRunner(),
        timeout: TimeInterval = 30,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.configurationDirectory = configurationDirectory
            ?? Self.defaultConfigurationDirectory(fileManager: fileManager)
        self.svnExecutable = svnExecutable
        self.runner = runner
        self.timeout = timeout
    }

    public func clearAll() async throws -> SvnAuthenticationCacheClearResult {
        let authenticationDirectory = configurationDirectory.appendingPathComponent("auth", isDirectory: true)
        var isDirectory: ObjCBool = false
        let authenticationDirectoryExists = fileManager.fileExists(
            atPath: authenticationDirectory.path,
            isDirectory: &isDirectory
        )
        if authenticationDirectoryExists, !isDirectory.boolValue {
            throw SvnAuthenticationCacheError.authenticationPathIsNotDirectory(authenticationDirectory)
        }

        let items: [URL]
        if authenticationDirectoryExists {
            items = try fileManager.contentsOfDirectory(
                at: authenticationDirectory,
                includingPropertiesForKeys: nil,
                options: []
            )
        } else {
            items = []
        }

        let result = try await runner.run(
            executable: svnExecutable,
            arguments: ["--config-dir", configurationDirectory.path, "auth", "--remove", "*"],
            stdin: nil,
            currentDirectory: nil,
            timeout: timeout
        )
        guard result.exitCode == 0 || Self.hasNoMatchingCredentials(result) else {
            throw SvnAuthenticationCacheError.commandFailed(
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }

        for item in items {
            if fileManager.fileExists(atPath: item.path) {
                try fileManager.removeItem(at: item)
            }
        }
        if authenticationDirectoryExists,
           !fileManager.fileExists(atPath: authenticationDirectory.path) {
            try fileManager.createDirectory(at: authenticationDirectory, withIntermediateDirectories: true)
        }
        return SvnAuthenticationCacheClearResult(
            authenticationDirectory: authenticationDirectory,
            removedFileCacheItemCount: items.count
        )
    }

    private static func hasNoMatchingCredentials(_ result: ProcessResult) -> Bool {
        result.stderr.contains("E200009")
    }

    private static func defaultConfigurationDirectory(fileManager: FileManager) -> URL {
        if let configured = ProcessInfo.processInfo.environment["SVN_CONFIG_DIR"], !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".subversion", isDirectory: true)
    }
}
