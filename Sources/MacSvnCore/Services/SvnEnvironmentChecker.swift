import Foundation

public protocol FileChecking: Sendable {
    func isExecutableFile(atPath path: String) -> Bool
}

public struct FileManagerFileChecker: FileChecking {
    public init() {}

    public func isExecutableFile(atPath path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}

public protocol SvnBackendFactory: Sendable {
    func makeBackend(svnExecutable: String) -> any SvnBackend
}

public struct DefaultSvnBackendFactory: SvnBackendFactory {
    public init() {}

    public func makeBackend(svnExecutable: String) -> any SvnBackend {
        SvnCliBackend(svnExecutable: svnExecutable, runner: ProcessRunner())
    }
}

public struct SvnEnvironmentChecker: Sendable {
    private let fileChecker: any FileChecking
    private let backendFactory: any SvnBackendFactory
    private let minimumVersion: SvnVersion
    private let candidatePaths: [String]

    public init(
        fileChecker: any FileChecking = FileManagerFileChecker(),
        backendFactory: any SvnBackendFactory = DefaultSvnBackendFactory(),
        minimumVersion: SvnVersion = SvnVersion(major: 1, minor: 14, patch: 0),
        candidatePaths: [String] = [
            "/opt/homebrew/bin/svn",
            "/usr/local/bin/svn",
            "/usr/bin/svn"
        ]
    ) {
        self.fileChecker = fileChecker
        self.backendFactory = backendFactory
        self.minimumVersion = minimumVersion
        self.candidatePaths = candidatePaths
    }

    public func check(configuredPath: String?) async -> SvnEnvironmentStatus {
        let paths = orderedPaths(configuredPath: configuredPath)
        var checkedPaths: [String] = []

        for path in paths {
            checkedPaths.append(path)

            guard fileChecker.isExecutableFile(atPath: path) else {
                continue
            }

            do {
                let version = try await backendFactory.makeBackend(svnExecutable: path).version()
                guard version >= minimumVersion else {
                    return .unsupportedVersion(path: path, version: version, minimum: minimumVersion)
                }

                return .available(path: path, version: version)
            } catch {
                continue
            }
        }

        return .missing(checkedPaths: checkedPaths)
    }

    private func orderedPaths(configuredPath: String?) -> [String] {
        var seen: Set<String> = []
        var paths: [String] = []

        func append(_ path: String?) {
            guard let path else {
                return
            }

            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                return
            }

            paths.append(trimmed)
        }

        append(configuredPath)
        candidatePaths.forEach { append($0) }
        return paths
    }
}
