import Foundation

public protocol CommitGuardChecking: Sendable {
    func evaluate(wc: URL, paths: [String]) async throws -> [CommitGuardIssue]
}

public struct CommitGuardService: CommitGuardChecking {
    private let configuration: CommitGuardConfiguration

    public init(configuration: CommitGuardConfiguration = CommitGuardConfiguration()) {
        self.configuration = configuration
    }

    public func evaluate(wc: URL, paths: [String]) async throws -> [CommitGuardIssue] {
        var issues: [CommitGuardIssue] = []

        for path in paths {
            let fileURL = wc.appendingPathComponent(path)
            var isDirectory: ObjCBool = false

            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else {
                continue
            }

            issues.append(contentsOf: try evaluatePathRules(path: path, fileURL: fileURL))
        }

        return issues
    }

    private func evaluatePathRules(path: String, fileURL: URL) throws -> [CommitGuardIssue] {
        var issues: [CommitGuardIssue] = []

        let fileSize = try fileSize(at: fileURL)
        if fileSize > configuration.largeFileThresholdBytes {
            issues.append(issue(
                ruleID: .largeFile,
                path: path,
                message: "Large file exceeds commit guard threshold.",
                detail: "\(fileSize) bytes > \(configuration.largeFileThresholdBytes) bytes"
            ))
        }

        if isDeniedPath(path) {
            issues.append(issue(
                ruleID: .deniedPath,
                path: path,
                message: "Path matches a denied commit pattern.",
                detail: nil
            ))
        }

        guard let text = try textContentsIfReadable(fileURL) else {
            return issues
        }

        if containsConflictMarker(text) {
            issues.insert(issue(
                ruleID: .conflictMarker,
                path: path,
                message: "Conflict marker remains in file.",
                detail: nil
            ), at: 0)
        }

        if containsSuspectedSecret(text) {
            issues.append(issue(
                ruleID: .suspectedSecret,
                path: path,
                message: "Possible secret or private key detected.",
                detail: nil
            ))
        }

        return issues
    }

    private func issue(ruleID: CommitGuardRuleID, path: String, message: String, detail: String?) -> CommitGuardIssue {
        CommitGuardIssue(
            ruleID: ruleID,
            severity: configuration.hardBlockedRules.contains(ruleID) ? .blocking : .warning,
            path: path,
            message: message,
            detail: detail
        )
    }

    private func fileSize(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int ?? 0
    }

    private func textContentsIfReadable(_ url: URL) throws -> String? {
        let data = try Data(contentsOf: url)
        guard !data.contains(0) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func containsConflictMarker(_ text: String) -> Bool {
        text.contains("<<<<<<<") && text.contains("=======") && text.contains(">>>>>>>")
    }

    private func containsSuspectedSecret(_ text: String) -> Bool {
        let patterns = [
            #"AKIA[0-9A-Z]{16}"#,
            #"ghp_[A-Za-z0-9_]{20,}"#,
            #"sk-[A-Za-z0-9_-]{20,}"#,
            #"BEGIN PRIVATE KEY"#
        ]

        return patterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func isDeniedPath(_ path: String) -> Bool {
        configuration.deniedPathPatterns.contains { pattern in
            matches(pattern: pattern, path: path)
        }
    }

    private func matches(pattern: String, path: String) -> Bool {
        if pattern == "node_modules/**" {
            return path == "node_modules"
                || path.hasPrefix("node_modules/")
                || path.contains("/node_modules/")
        }

        if !pattern.contains("/") && !pattern.contains("*") {
            return path == pattern || path.split(separator: "/").last.map(String.init) == pattern
        }

        if !pattern.contains("/") {
            let basename = path.split(separator: "/").last.map(String.init) ?? path
            return wildcard(pattern, matches: basename) || wildcard(pattern, matches: path)
        }

        return wildcard(pattern, matches: path)
    }

    private func wildcard(_ pattern: String, matches value: String) -> Bool {
        var regex = "^"
        var iterator = pattern.makeIterator()

        while let character = iterator.next() {
            if character == "*" {
                if let next = iterator.next() {
                    if next == "*" {
                        regex += ".*"
                    } else {
                        regex += "[^/]*" + NSRegularExpression.escapedPattern(for: String(next))
                    }
                } else {
                    regex += "[^/]*"
                }
            } else {
                regex += NSRegularExpression.escapedPattern(for: String(character))
            }
        }

        regex += "$"
        return value.range(of: regex, options: .regularExpression) != nil
    }
}
