import Foundation

public struct SvnConfigurationDirectoryResolver: Sendable {
    private let overrideURL: URL?
    private let environment: [String: String]
    private let homeDirectoryURL: URL

    public init(
        overrideURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.overrideURL = overrideURL
        self.environment = environment
        self.homeDirectoryURL = homeDirectoryURL
    }

    public func resolve() -> URL {
        if let overrideURL { return overrideURL.standardizedFileURL }
        if let configured = environment["SVN_CONFIG_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true).standardizedFileURL
        }
        return homeDirectoryURL
            .appendingPathComponent(".subversion", isDirectory: true)
            .standardizedFileURL
    }
}

public struct SvnClientManagedConfiguration: Equatable, Sendable {
    public var globalIgnorePatterns: [String]
    public var useCommitTimes: Bool
    public var network: SvnNetworkSettings
    public var proxyPassword: String

    public init(
        globalIgnorePatterns: [String] = [],
        useCommitTimes: Bool = false,
        network: SvnNetworkSettings = SvnNetworkSettings(),
        proxyPassword: String = ""
    ) {
        self.globalIgnorePatterns = globalIgnorePatterns
        self.useCommitTimes = useCommitTimes
        self.network = network
        self.proxyPassword = proxyPassword
    }
}

public enum SvnClientConfigurationError: Error, Equatable, Sendable {
    case invalidValue(String)
    case invalidProxyPort(Int)
}

/// Reads and edits only the SVN keys owned by the settings UI while preserving all other INI content.
public struct SvnClientConfigurationStore: Sendable {
    public let directoryURL: URL
    public let configFileURL: URL
    public let serversFileURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL.standardizedFileURL
        self.configFileURL = self.directoryURL.appendingPathComponent("config", isDirectory: false)
        self.serversFileURL = self.directoryURL.appendingPathComponent("servers", isDirectory: false)
    }

    public init(resolver: SvnConfigurationDirectoryResolver = SvnConfigurationDirectoryResolver()) {
        self.init(directoryURL: resolver.resolve())
    }

    public func load() throws -> SvnClientManagedConfiguration {
        let config = try IniDocument(contentsOf: configFileURL)
        let servers = try IniDocument(contentsOf: serversFileURL)
        let globalIgnores = config.value(section: "miscellany", key: "global-ignores")?
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init) ?? []
        let useCommitTimes = Self.boolValue(
            config.value(section: "miscellany", key: "use-commit-times")
        )

        let proxyHost = servers.value(section: "global", key: "http-proxy-host") ?? ""
        let proxy = SvnProxySettings(
            enabled: !proxyHost.isEmpty,
            host: proxyHost,
            port: Int(servers.value(section: "global", key: "http-proxy-port") ?? "") ?? 8080,
            exceptions: (servers.value(section: "global", key: "http-proxy-exceptions") ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            username: servers.value(section: "global", key: "http-proxy-username") ?? ""
        )
        let tunnelTokens = Self.parseCommandLine(
            config.value(section: "tunnels", key: "ssh") ?? ""
        )
        let sshPath = tunnelTokens.first.flatMap { $0.isEmpty ? nil : $0 }
        let network = SvnNetworkSettings(
            proxy: proxy,
            sshExecutablePath: sshPath,
            sshArguments: tunnelTokens.isEmpty ? [] : Array(tunnelTokens.dropFirst())
        )
        return SvnClientManagedConfiguration(
            globalIgnorePatterns: globalIgnores,
            useCommitTimes: useCommitTimes,
            network: network,
            proxyPassword: servers.value(section: "global", key: "http-proxy-password") ?? ""
        )
    }

    public func ensureFilesExist() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: configFileURL.path) {
            try Data().write(to: configFileURL, options: .atomic)
        }
        if !FileManager.default.fileExists(atPath: serversFileURL.path) {
            try Data().write(to: serversFileURL, options: .atomic)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: serversFileURL.path)
    }

    public func update(_ configuration: SvnClientManagedConfiguration) throws {
        let normalized = try Self.validateAndNormalize(configuration)
        var config = try IniDocument(contentsOf: configFileURL)
        var servers = try IniDocument(contentsOf: serversFileURL)

        config.set(
            section: "miscellany",
            values: [
                "global-ignores": normalized.globalIgnorePatterns.joined(separator: " "),
                "use-commit-times": normalized.useCommitTimes ? "yes" : "no",
            ]
        )
        let sshCommand: String?
        if let executable = normalized.network.sshExecutablePath {
            sshCommand = ([executable] + normalized.network.sshArguments)
                .map(Self.quoteCommandToken)
                .joined(separator: " ")
        } else {
            sshCommand = nil
        }
        config.set(section: "tunnels", values: ["ssh": sshCommand])

        let proxy = normalized.network.proxy
        servers.set(
            section: "global",
            values: [
                "http-proxy-host": proxy.enabled ? proxy.host : nil,
                "http-proxy-port": proxy.enabled ? String(proxy.port) : nil,
                "http-proxy-exceptions": proxy.enabled && !proxy.exceptions.isEmpty
                    ? proxy.exceptions.joined(separator: ", ") : nil,
                "http-proxy-username": proxy.enabled && !proxy.username.isEmpty ? proxy.username : nil,
                "http-proxy-password": proxy.enabled && !normalized.proxyPassword.isEmpty
                    ? normalized.proxyPassword : nil,
            ]
        )

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try config.write(to: configFileURL)
        try servers.write(to: serversFileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: serversFileURL.path)
    }

    private static func validateAndNormalize(
        _ configuration: SvnClientManagedConfiguration
    ) throws -> SvnClientManagedConfiguration {
        var result = configuration
        result.globalIgnorePatterns = try configuration.globalIgnorePatterns.map { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.contains(where: \Character.isWhitespace),
                  isSafeValue(trimmed) else {
                throw SvnClientConfigurationError.invalidValue("global-ignores")
            }
            return trimmed
        }

        var proxy = configuration.network.proxy
        proxy.host = proxy.host.trimmingCharacters(in: .whitespacesAndNewlines)
        proxy.username = proxy.username.trimmingCharacters(in: .whitespacesAndNewlines)
        proxy.exceptions = proxy.exceptions.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        if proxy.enabled {
            guard !proxy.host.isEmpty, isSafeValue(proxy.host) else {
                throw SvnClientConfigurationError.invalidValue("http-proxy-host")
            }
            guard (1...65_535).contains(proxy.port) else {
                throw SvnClientConfigurationError.invalidProxyPort(proxy.port)
            }
        }
        guard isSafeValue(proxy.username), proxy.exceptions.allSatisfy(isSafeValue) else {
            throw SvnClientConfigurationError.invalidValue("http-proxy")
        }
        guard isSafeValue(configuration.proxyPassword) else {
            throw SvnClientConfigurationError.invalidValue("http-proxy-password")
        }
        if !proxy.enabled {
            result.proxyPassword = ""
        }
        result.network.proxy = proxy

        let sshPath = configuration.network.sshExecutablePath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let sshPath, !sshPath.isEmpty {
            guard isSafeValue(sshPath), configuration.network.sshArguments.allSatisfy(isSafeValue) else {
                throw SvnClientConfigurationError.invalidValue("ssh")
            }
            result.network.sshExecutablePath = sshPath
        } else {
            result.network.sshExecutablePath = nil
            result.network.sshArguments = []
        }
        return result
    }

    private static func isSafeValue(_ value: String) -> Bool {
        !value.contains("\n") && !value.contains("\r") && !value.contains("\0")
    }

    private static func boolValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["yes", "true", "on", "1"].contains(value.lowercased())
    }

    private static func quoteCommandToken(_ value: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./=:@%+,-")
        if !value.isEmpty, value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func parseCommandLine(_ command: String) -> [String] {
        enum Quote { case none, single, double }
        var quote = Quote.none
        var escaping = false
        var current = ""
        var tokens: [String] = []
        var started = false
        for character in command {
            if escaping {
                current.append(character)
                escaping = false
                started = true
                continue
            }
            switch quote {
            case .single:
                if character == "'" { quote = .none } else { current.append(character) }
                started = true
            case .double:
                if character == "\"" {
                    quote = .none
                } else if character == "\\" {
                    escaping = true
                } else {
                    current.append(character)
                }
                started = true
            case .none:
                if character == "'" {
                    quote = .single
                    started = true
                } else if character == "\"" {
                    quote = .double
                    started = true
                } else if character == "\\" {
                    escaping = true
                    started = true
                } else if character.isWhitespace {
                    if started {
                        tokens.append(current)
                        current = ""
                        started = false
                    }
                } else {
                    current.append(character)
                    started = true
                }
            }
        }
        if escaping { current.append("\\") }
        if started { tokens.append(current) }
        return tokens
    }
}

private struct IniDocument {
    private var lines: [String]
    private let newline: String

    init(contentsOf url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            lines = []
            newline = "\n"
            return
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        newline = text.contains("\r\n") ? "\r\n" : "\n"
        lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    func value(section: String, key: String) -> String? {
        guard let bounds = sectionBounds(named: section) else { return nil }
        for index in bounds.content {
            if let parsed = Self.keyValue(in: lines[index]), parsed.key.caseInsensitiveCompare(key) == .orderedSame {
                return parsed.value
            }
        }
        return nil
    }

    mutating func set(section: String, values: [String: String?]) {
        for key in values.keys.sorted() {
            set(section: section, key: key, value: values[key] ?? nil)
        }
    }

    mutating func write(to url: URL) throws {
        let text = lines.joined(separator: newline)
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    private mutating func set(section: String, key: String, value: String?) {
        if let bounds = sectionBounds(named: section) {
            let matchingIndices = bounds.content.filter {
                guard let parsed = Self.keyValue(in: lines[$0]) else { return false }
                return parsed.key.caseInsensitiveCompare(key) == .orderedSame
            }
            if let index = matchingIndices.first {
                if let value {
                    lines[index] = "\(key) = \(value)"
                }
                for duplicateIndex in matchingIndices.dropFirst().reversed() {
                    lines.remove(at: duplicateIndex)
                }
                if value == nil {
                    lines.remove(at: index)
                }
                return
            }
            if let value {
                lines.insert("\(key) = \(value)", at: bounds.end)
            }
            return
        }

        guard let value else { return }
        if !lines.isEmpty, lines.last?.isEmpty == false { lines.append("") }
        lines.append("[\(section)]")
        lines.append("\(key) = \(value)")
    }

    private func sectionBounds(named name: String) -> (content: Range<Int>, end: Int)? {
        var start: Int?
        for (index, line) in lines.enumerated() {
            guard let section = Self.sectionName(in: line) else { continue }
            if let start {
                return (start..<index, index)
            }
            if section.caseInsensitiveCompare(name) == .orderedSame {
                start = index + 1
            }
        }
        if let start { return (start..<lines.count, lines.count) }
        return nil
    }

    private static func sectionName(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == "[", trimmed.last == "]", trimmed.count > 2 else { return nil }
        return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    private static func keyValue(in line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix(";"),
              let separator = trimmed.firstIndex(of: "=") else { return nil }
        let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
        let value = String(trimmed[trimmed.index(after: separator)...])
            .trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : (key, value)
    }
}
