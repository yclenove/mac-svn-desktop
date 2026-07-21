import Foundation

public struct SvnShelf: Equatable, Identifiable, Sendable {
    public let name: String
    public let latestVersion: Int
    public let pathCount: Int
    public let ageSummary: String
    public let message: String?

    public var id: String { name }

    public init(
        name: String,
        latestVersion: Int,
        pathCount: Int,
        ageSummary: String,
        message: String?
    ) {
        self.name = name
        self.latestVersion = latestVersion
        self.pathCount = pathCount
        self.ageSummary = ageSummary
        self.message = message
    }
}

public enum SvnShelvingAvailability: Equatable, Sendable {
    case available(SvnShelvingVersion)
    case unavailable(SvnShelvingVersion, reason: String)
}

public enum SvnShelfListParser {
    public static func parse(_ output: String) throws -> [SvnShelf] {
        let pattern = #"^(.+?)\s+version\s+(\d+),\s+(.+?),\s+(\d+)\s+paths?\s+changed$"#
        let expression = try NSRegularExpression(pattern: pattern)
        var shelves: [SvnShelf] = []

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            guard !rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if rawLine.first?.isWhitespace == true {
                guard let last = shelves.popLast() else {
                    throw SvnError.parse(detail: "Shelf message appears before a shelf entry")
                }
                shelves.append(SvnShelf(
                    name: last.name,
                    latestVersion: last.latestVersion,
                    pathCount: last.pathCount,
                    ageSummary: last.ageSummary,
                    message: rawLine.trimmingCharacters(in: .whitespaces)
                ))
                continue
            }

            let range = NSRange(rawLine.startIndex..<rawLine.endIndex, in: rawLine)
            guard let match = expression.firstMatch(in: rawLine, range: range),
                  let nameRange = Range(match.range(at: 1), in: rawLine),
                  let versionRange = Range(match.range(at: 2), in: rawLine),
                  let ageRange = Range(match.range(at: 3), in: rawLine),
                  let countRange = Range(match.range(at: 4), in: rawLine),
                  let version = Int(rawLine[versionRange]),
                  let pathCount = Int(rawLine[countRange]) else {
                throw SvnError.parse(detail: "Invalid shelf list line: \(rawLine)")
            }
            shelves.append(SvnShelf(
                name: rawLine[nameRange].trimmingCharacters(in: .whitespaces),
                latestVersion: version,
                pathCount: pathCount,
                ageSummary: String(rawLine[ageRange]),
                message: nil
            ))
        }
        return shelves
    }
}

public protocol SvnExperimentalShelvingProviding: Sendable {
    var version: SvnShelvingVersion { get }
    func availability(wc: URL) async -> SvnShelvingAvailability
    func list(wc: URL) async throws -> [SvnShelf]
    func shelve(wc: URL, name: String, paths: [String], message: String, keepLocal: Bool) async throws
    func diff(wc: URL, name: String, version: Int?) async throws -> String
    func log(wc: URL, name: String) async throws -> String
    func unshelve(wc: URL, name: String, version: Int?, drop: Bool) async throws
    func drop(wc: URL, name: String) async throws
}

public struct SvnExperimentalShelvingClient: SvnExperimentalShelvingProviding {
    public let version: SvnShelvingVersion

    private let svnExecutable: String
    private let runner: any ProcessRunning
    private let timeout: TimeInterval

    public init(
        svnExecutable: String,
        runner: any ProcessRunning,
        timeout: TimeInterval = 120,
        version: SvnShelvingVersion
    ) {
        self.svnExecutable = svnExecutable
        self.runner = runner
        self.timeout = timeout
        self.version = version
    }

    public func availability(wc: URL) async -> SvnShelvingAvailability {
        do {
            let result = try await runRaw(arguments: ["help", "x-shelve"], wc: wc)
            guard result.exitCode == 0 else {
                let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return .unavailable(version, reason: reason.isEmpty ? "x-shelve unavailable" : reason)
            }
            return .available(version)
        } catch {
            return .unavailable(version, reason: String(describing: error))
        }
    }

    public func list(wc: URL) async throws -> [SvnShelf] {
        let result = try await run(SvnCommandBuilder.experimentalShelfList(), wc: wc)
        return try SvnShelfListParser.parse(String(decoding: result.stdout, as: UTF8.self))
    }

    public func shelve(
        wc: URL,
        name: String,
        paths: [String],
        message: String,
        keepLocal: Bool
    ) async throws {
        _ = try await run(SvnCommandBuilder.experimentalShelve(
            name: name,
            paths: paths,
            message: message,
            keepLocal: keepLocal
        ), wc: wc)
    }

    public func diff(wc: URL, name: String, version: Int?) async throws -> String {
        let result = try await run(
            SvnCommandBuilder.experimentalShelfDiff(name: name, version: version),
            wc: wc
        )
        return String(decoding: result.stdout, as: UTF8.self)
    }

    public func log(wc: URL, name: String) async throws -> String {
        let result = try await run(SvnCommandBuilder.experimentalShelfLog(name: name), wc: wc)
        return String(decoding: result.stdout, as: UTF8.self)
    }

    public func unshelve(wc: URL, name: String, version: Int?, drop: Bool) async throws {
        _ = try await run(
            SvnCommandBuilder.experimentalUnshelve(name: name, version: version, drop: drop),
            wc: wc
        )
    }

    public func drop(wc: URL, name: String) async throws {
        _ = try await run(SvnCommandBuilder.experimentalShelfDrop(name: name), wc: wc)
    }

    private func run(_ command: SvnCommand, wc: URL) async throws -> ProcessResult {
        let result = try await runRaw(arguments: command.arguments, wc: wc)
        guard result.exitCode == 0 else {
            throw SvnErrorMapper.map(exitCode: result.exitCode, stderr: result.stderr)
        }
        return result
    }

    private func runRaw(arguments: [String], wc: URL) async throws -> ProcessResult {
        try await runner.run(
            executable: "/usr/bin/env",
            arguments: ["SVN_EXPERIMENTAL_COMMANDS=\(version.environmentValue)", svnExecutable] + arguments,
            stdin: nil,
            currentDirectory: wc.path,
            timeout: timeout
        )
    }
}
