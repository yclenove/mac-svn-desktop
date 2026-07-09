import Foundation

public struct GitMigrationEnvironmentChecker: Sendable {
    private let gitExecutable: String
    private let runner: any ProcessRunning
    private let timeout: TimeInterval

    public init(
        gitExecutable: String = "git",
        runner: any ProcessRunning,
        timeout: TimeInterval = 120
    ) {
        self.gitExecutable = gitExecutable
        self.runner = runner
        self.timeout = timeout
    }

    public func check() async throws -> GitMigrationEnvironmentStatus {
        let git = try await checkTool(arguments: ["--version"])
        let gitSvn = try await checkTool(arguments: ["svn", "--version"])

        return GitMigrationEnvironmentStatus(git: git, gitSvn: gitSvn)
    }

    private func checkTool(arguments: [String]) async throws -> GitMigrationToolStatus {
        let result = try await runner.run(
            executable: gitExecutable,
            arguments: arguments,
            stdin: nil,
            currentDirectory: nil,
            timeout: timeout
        )

        if result.exitCode == 0 {
            return GitMigrationToolStatus(
                isAvailable: true,
                versionOutput: cleanOutput(result.stdout),
                errorSummary: nil
            )
        }

        return GitMigrationToolStatus(
            isAvailable: false,
            versionOutput: nil,
            errorSummary: cleanError(result)
        )
    }

    private func cleanOutput(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanError(_ result: ProcessResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }

        let stdout = cleanOutput(result.stdout)
        if !stdout.isEmpty {
            return stdout
        }

        return "Command exited with code \(result.exitCode)."
    }
}
