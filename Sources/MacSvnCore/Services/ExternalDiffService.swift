import Foundation

public protocol ExternalDiffContentProviding: Sendable {
    func info(wc: URL, target: String) async throws -> SvnInfo
    func cat(url: String, revision: Revision?, sizeLimit: Int, auth: Credential?) async throws -> Data
}

public protocol ExternalDiffOpening: Sendable {
    func open(
        wc: URL,
        target: String,
        tool: ExternalDiffToolConfiguration,
        r1: Revision?,
        r2: Revision?
    ) async throws -> ExternalDiffLaunchResult
}

public struct ExternalDiffLaunchResult: Equatable, Sendable {
    public let leftFile: URL
    public let rightFile: URL
    public let processResult: ProcessResult

    public init(leftFile: URL, rightFile: URL, processResult: ProcessResult) {
        self.leftFile = leftFile
        self.rightFile = rightFile
        self.processResult = processResult
    }
}

public struct ExternalDiffService: ExternalDiffOpening {
    private let contentProvider: any ExternalDiffContentProviding
    private let runner: any ProcessRunning
    private let temporaryDirectory: URL
    private let sizeLimit: Int
    private let timeout: TimeInterval

    public init(
        contentProvider: any ExternalDiffContentProviding,
        runner: any ProcessRunning,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSvnExternalDiff", isDirectory: true),
        sizeLimit: Int = 10 * 1024 * 1024,
        timeout: TimeInterval = 120
    ) {
        self.contentProvider = contentProvider
        self.runner = runner
        self.temporaryDirectory = temporaryDirectory
        self.sizeLimit = sizeLimit
        self.timeout = timeout
    }

    public func open(
        wc: URL,
        target: String,
        tool: ExternalDiffToolConfiguration,
        r1: Revision?,
        r2: Revision?
    ) async throws -> ExternalDiffLaunchResult {
        try await open(wc: wc, target: target, tool: tool, r1: r1, r2: r2, auth: nil)
    }

    public func open(
        wc: URL,
        target: String,
        tool: ExternalDiffToolConfiguration,
        r1: Revision?,
        r2: Revision?,
        auth: Credential?
    ) async throws -> ExternalDiffLaunchResult {
        let info = try await contentProvider.info(wc: wc, target: target)
        let leftFile = try await materializeRevisionFile(
            url: info.url,
            target: target,
            revision: r1 ?? info.revision,
            side: "left",
            auth: auth
        )
        let rightFile: URL

        if let r2 {
            rightFile = try await materializeRevisionFile(
                url: info.url,
                target: target,
                revision: r2,
                side: "right",
                auth: auth
            )
        } else {
            rightFile = wc.appendingPathComponent(target)
        }

        let processResult = try await runner.run(
            executable: tool.executablePath,
            arguments: ExternalToolArgumentResolver.resolve(
                template: tool.arguments,
                defaultArguments: ["{left}", "{right}"],
                replacements: ["{left}": leftFile, "{right}": rightFile]
            ),
            stdin: nil,
            currentDirectory: nil,
            timeout: timeout
        )
        guard processResult.exitCode == 0 else {
            throw ExternalToolLaunchError.commandFailed(
                exitCode: processResult.exitCode,
                stderr: processResult.stderr
            )
        }

        return ExternalDiffLaunchResult(leftFile: leftFile, rightFile: rightFile, processResult: processResult)
    }

    private func materializeRevisionFile(
        url: String,
        target: String,
        revision: Revision?,
        side: String,
        auth: Credential?
    ) async throws -> URL {
        let data = try await contentProvider.cat(
            url: url,
            revision: revision,
            sizeLimit: sizeLimit,
            auth: auth
        )
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        let basename = URL(fileURLWithPath: target).lastPathComponent
        let file = temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(side)-\(basename)")
        try data.write(to: file, options: .atomic)
        return file
    }
}

extension SvnService: ExternalDiffContentProviding {}
