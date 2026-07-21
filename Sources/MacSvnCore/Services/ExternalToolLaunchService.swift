import Foundation

public struct ExternalToolLaunchResult: Equatable, Sendable {
    public let processResult: ProcessResult

    public init(processResult: ProcessResult) {
        self.processResult = processResult
    }
}

public enum ExternalToolLaunchError: Error, Equatable, Sendable {
    case missingTextConflictArtifacts(path: String)
    case missingWorkingCopyFile(path: String)
    case targetOutsideWorkingCopy(path: String)
    case commandFailed(exitCode: Int32, stderr: String)
}

extension ExternalToolLaunchError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingTextConflictArtifacts(let path):
            return "缺少文本冲突侧文件：\(path)"
        case .missingWorkingCopyFile(let path):
            return "工作副本文件不存在：\(path)"
        case .targetOutsideWorkingCopy(let path):
            return "外置工具目标不在工作副本内：\(path)"
        case .commandFailed(let exitCode, let stderr):
            return "外置程序失败（退出码 \(exitCode)）：\(stderr)"
        }
    }
}

public enum ExternalToolArgumentResolver {
    public static func resolve(
        template: [String],
        defaultArguments: [String],
        replacements: [String: URL]
    ) -> [String] {
        let source = template.isEmpty ? defaultArguments : template
        return source.map { argument in
            replacements.reduce(into: argument) { value, replacement in
                value = value.replacingOccurrences(of: replacement.key, with: replacement.value.path)
            }
        }
    }
}

public protocol ExternalMergeOpening: Sendable {
    func openMerge(
        wc: URL,
        conflict: ConflictInfo,
        tool: ExternalDiffToolConfiguration
    ) async throws -> ExternalToolLaunchResult
}

public protocol ExternalBlameOpening: Sendable {
    func openBlame(
        wc: URL,
        target: String,
        tool: ExternalDiffToolConfiguration
    ) async throws -> ExternalToolLaunchResult
}

/// 启动按规则选择的外置 Merge/Blame，不替用户标记冲突已解决。
public struct ExternalToolLaunchService: ExternalMergeOpening, ExternalBlameOpening {
    private let runner: any ProcessRunning
    private let timeout: TimeInterval

    public init(
        runner: any ProcessRunning = ProcessRunner(),
        timeout: TimeInterval = 120
    ) {
        self.runner = runner
        self.timeout = timeout
    }

    public func openMerge(
        wc: URL,
        conflict: ConflictInfo,
        tool: ExternalDiffToolConfiguration
    ) async throws -> ExternalToolLaunchResult {
        guard conflict.kind == .text,
              let base = existingFile(conflict.baseFile),
              let mine = existingFile(conflict.mineFile),
              let theirs = existingFile(conflict.theirsFile)
        else {
            throw ExternalToolLaunchError.missingTextConflictArtifacts(path: conflict.path)
        }
        let result = try workingCopyFile(wc: wc, target: conflict.path)
        guard FileManager.default.fileExists(atPath: result.path) else {
            throw ExternalToolLaunchError.missingTextConflictArtifacts(path: conflict.path)
        }

        let arguments = ExternalToolArgumentResolver.resolve(
            template: tool.arguments,
            defaultArguments: ["{base}", "{mine}", "{theirs}", "{result}"],
            replacements: [
                "{base}": base,
                "{mine}": mine,
                "{theirs}": theirs,
                "{result}": result,
            ]
        )
        return try await launch(tool: tool, arguments: arguments, currentDirectory: wc.path)
    }

    public func openBlame(
        wc: URL,
        target: String,
        tool: ExternalDiffToolConfiguration
    ) async throws -> ExternalToolLaunchResult {
        let file = try workingCopyFile(wc: wc, target: target)
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw ExternalToolLaunchError.missingWorkingCopyFile(path: target)
        }
        let arguments = ExternalToolArgumentResolver.resolve(
            template: tool.arguments,
            defaultArguments: ["{file}"],
            replacements: ["{file}": file]
        )
        return try await launch(tool: tool, arguments: arguments, currentDirectory: wc.path)
    }

    private func launch(
        tool: ExternalDiffToolConfiguration,
        arguments: [String],
        currentDirectory: String
    ) async throws -> ExternalToolLaunchResult {
        let result = try await runner.run(
            executable: tool.executablePath,
            arguments: arguments,
            stdin: nil,
            currentDirectory: currentDirectory,
            timeout: timeout
        )
        guard result.exitCode == 0 else {
            throw ExternalToolLaunchError.commandFailed(
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return ExternalToolLaunchResult(processResult: result)
    }

    private func existingFile(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func workingCopyFile(wc: URL, target: String) throws -> URL {
        let root = wc.standardizedFileURL
        let file = target.hasPrefix("/")
            ? URL(fileURLWithPath: target).standardizedFileURL
            : root.appendingPathComponent(target).standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard file.path.hasPrefix(rootPath) else {
            throw ExternalToolLaunchError.targetOutsideWorkingCopy(path: target)
        }
        return file
    }
}
