import Foundation

public enum ClientHookType: String, Codable, CaseIterable, Equatable, Sendable {
    case preCommit
    case postUpdate

    public var displayName: String {
        switch self {
        case .preCommit: "Pre-commit"
        case .postUpdate: "Post-update"
        }
    }
}

public struct ClientHookConfiguration: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var type: ClientHookType
    public var workingCopyPath: String
    public var executablePath: String
    public var arguments: [String]
    public var isEnabled: Bool
    public var timeout: TimeInterval

    public init(
        id: UUID = UUID(),
        type: ClientHookType,
        workingCopyPath: String,
        executablePath: String,
        arguments: [String] = [],
        isEnabled: Bool = true,
        timeout: TimeInterval = 120
    ) {
        self.id = id
        self.type = type
        self.workingCopyPath = workingCopyPath
        self.executablePath = executablePath
        self.arguments = arguments
        self.isEnabled = isEnabled
        self.timeout = timeout
    }
}

public enum ClientHookError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    case invalidConfiguration(type: ClientHookType, message: String)
    case failed(type: ClientHookType, exitCode: Int32, message: String)
    case launchFailed(type: ClientHookType, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let type, let message):
            "\(type.displayName) 客户端钩子配置无效：\(message)"
        case .failed(let type, let exitCode, let message):
            "\(type.displayName) 客户端钩子失败（退出码 \(exitCode)）：\(message)"
        case .launchFailed(let type, let message):
            "无法启动 \(type.displayName) 客户端钩子：\(message)"
        }
    }

    public var description: String { errorDescription ?? "Client hook failed." }
}

public protocol ClientHookRunning: Sendable {
    func runPreCommit(
        wc: URL,
        paths: [String],
        message: String,
        depth: SvnDepth
    ) async throws

    func runPostUpdate(
        wc: URL,
        paths: [String],
        depth: SvnDepth,
        revision: Revision?,
        errorMessage: String,
        touchedPaths: [String]
    ) async throws
}

public actor ClientHookService: ClientHookRunning {
    private let configurations: [ClientHookConfiguration]
    private let runner: any ProcessRunning

    public init(
        configurations: [ClientHookConfiguration],
        runner: any ProcessRunning = ProcessRunner()
    ) {
        self.configurations = configurations
        self.runner = runner
    }

    public func runPreCommit(
        wc: URL,
        paths: [String],
        message: String,
        depth: SvnDepth
    ) async throws {
        for configuration in matchingConfigurations(type: .preCommit, wc: wc) {
            let temporaryDirectory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

            let pathFile = try writeTemporaryFile(
                named: "paths.txt",
                contents: pathFileContents(wc: wc, paths: paths),
                in: temporaryDirectory
            )
            let messageFile = try writeTemporaryFile(
                named: "message.txt",
                contents: message,
                in: temporaryDirectory
            )
            try await execute(
                configuration,
                generatedArguments: [pathFile.path, depth.tortoiseHookCode, messageFile.path, wc.path],
                wc: wc
            )
        }
    }

    public func runPostUpdate(
        wc: URL,
        paths: [String],
        depth: SvnDepth,
        revision: Revision?,
        errorMessage: String,
        touchedPaths: [String]
    ) async throws {
        for configuration in matchingConfigurations(type: .postUpdate, wc: wc) {
            let temporaryDirectory = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

            let pathFile = try writeTemporaryFile(
                named: "paths.txt",
                contents: pathFileContents(wc: wc, paths: paths),
                in: temporaryDirectory
            )
            let errorFile = try writeTemporaryFile(
                named: "error.txt",
                contents: errorMessage,
                in: temporaryDirectory
            )
            let resultFile = try writeTemporaryFile(
                named: "results.txt",
                contents: pathFileContents(wc: wc, paths: touchedPaths),
                in: temporaryDirectory
            )
            try await execute(
                configuration,
                generatedArguments: [
                    pathFile.path,
                    depth.tortoiseHookCode,
                    revision.map { String($0.value) } ?? "",
                    errorFile.path,
                    wc.path,
                    resultFile.path
                ],
                wc: wc
            )
        }
    }

    private func matchingConfigurations(type: ClientHookType, wc: URL) -> [ClientHookConfiguration] {
        let workingCopyPath = wc.standardizedFileURL.path
        let matches = configurations.compactMap { configuration -> (ClientHookConfiguration, Int)? in
            guard configuration.isEnabled, configuration.type == type else { return nil }
            let configuredScope = configuration.workingCopyPath
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !configuredScope.isEmpty else { return nil }
            let scope = URL(fileURLWithPath: configuredScope).standardizedFileURL.path
            guard workingCopyPath == scope
                    || workingCopyPath.hasPrefix(scope == "/" ? "/" : scope + "/") else {
                return nil
            }
            return (configuration, scope.count)
        }
        guard let nearestLength = matches.map(\.1).max() else { return [] }
        return matches.filter { $0.1 == nearestLength }.map(\.0)
    }

    private func execute(
        _ configuration: ClientHookConfiguration,
        generatedArguments: [String],
        wc: URL
    ) async throws {
        let executable = configuration.executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !executable.isEmpty else {
            throw ClientHookError.invalidConfiguration(
                type: configuration.type,
                message: "Executable path is empty."
            )
        }
        do {
            let result = try await runner.run(
                executable: executable,
                arguments: configuration.arguments + generatedArguments,
                stdin: nil,
                currentDirectory: wc.path,
                timeout: max(1, configuration.timeout)
            )
            guard result.exitCode == 0 else {
                let stdout = String(decoding: result.stdout, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw ClientHookError.failed(
                    type: configuration.type,
                    exitCode: result.exitCode,
                    message: stderr.isEmpty ? (stdout.isEmpty ? "Hook exited with code \(result.exitCode)." : stdout) : stderr
                )
            }
        } catch let error as ClientHookError {
            throw error
        } catch {
            throw ClientHookError.launchFailed(type: configuration.type, message: error.localizedDescription)
        }
    }

    private func pathFileContents(wc: URL, paths: [String]) -> String {
        let targets = paths.isEmpty ? [wc.path] : paths.map { path in
            path.hasPrefix("/") ? path : wc.appendingPathComponent(path).standardizedFileURL.path
        }
        return targets.joined(separator: "\n") + "\n"
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SVNStudio-ClientHook-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeTemporaryFile(named name: String, contents: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
}

private extension SvnDepth {
    var tortoiseHookCode: String {
        switch self {
        case .empty: "0"
        case .files: "1"
        case .immediates: "2"
        case .infinity: "3"
        }
    }
}
