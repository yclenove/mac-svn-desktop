import Foundation

/// 按当前操作路径读取已合并的项目属性，供 UI 绑定工作副本层级实现。
public typealias ProjectPropertyLoading = @Sendable ([String]) async throws -> ProjectPropertyPolicy

/// TortoiseSVN 项目属性的可恢复解析诊断。无效配置不会让日常 SVN 操作崩溃。
public enum ProjectPropertyDiagnostic: Equatable, Sendable {
    case invalidNonNegativeInteger(name: String, value: String)
    case invalidBoolean(name: String, value: String)
    case invalidBugtraqRegex(value: String)
    case invalidBugtraqRegexLineCount(Int)
    case bugtraqMessageMissingPlaceholder
    case bugtraqRepositoryRootUnavailable
    case conflictingProjectProperty(String)
}

public enum ProjectLogTemplateOperation: String, CaseIterable, Hashable, Sendable {
    case commit
    case branch
    case `import`
    case delete
    case move
    case mkdir
    case propset
    case lock

    fileprivate var propertyName: String {
        "tsvn:logtemplate\(rawValue)"
    }
}

public struct ProjectLogTemplates: Equatable, Sendable {
    public let generic: String?
    private let operationSpecific: [ProjectLogTemplateOperation: String]

    public init(generic: String?, operationSpecific: [ProjectLogTemplateOperation: String] = [:]) {
        self.generic = generic
        self.operationSpecific = operationSpecific
    }

    public func initialMessage(for operation: ProjectLogTemplateOperation) -> String? {
        operationSpecific[operation] ?? generic
    }

    public func specificTemplate(for operation: ProjectLogTemplateOperation) -> String? {
        operationSpecific[operation]
    }
}

public enum ProjectSpellcheckLanguage {
    public static func resolve(_ projectLanguage: String?) -> String? {
        guard let projectLanguage else { return nil }
        let trimmed = projectLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let hexadecimal = trimmed.lowercased().hasPrefix("0x")
            ? String(trimmed.dropFirst(2))
            : nil
        guard let hexadecimal, let windowsLocaleCode = Int(hexadecimal, radix: 16) else {
            return trimmed
        }

        let matching = Locale.availableIdentifiers.filter {
            Locale.windowsLocaleCode(fromIdentifier: $0) == windowsLocaleCode
        }
        if matching.contains("en_US"), windowsLocaleCode == 0x0409 {
            return "en_US"
        }
        return matching.sorted().first
    }
}

public struct ProjectMessageValidationError: Equatable, Sendable {
    public let required: Int
    public let actual: Int

    public init(required: Int, actual: Int) {
        self.required = required
        self.actual = actual
    }

    public static func belowMinimumLength(required: Int, actual: Int) -> ProjectMessageValidationError {
        ProjectMessageValidationError(required: required, actual: actual)
    }
}

public struct BugtraqIssueReference: Equatable, Sendable, Identifiable {
    public let identifier: String
    /// 已解析的绝对或相对 URL；未配置 `bugtraq:url` 时为 `nil`。
    public let url: String?

    public init(identifier: String, url: String?) {
        self.identifier = identifier
        self.url = url
    }

    public var id: String { identifier }
}

public struct CommitProjectProperties: Equatable, Sendable {
    public let minimumMessageLength: Int?
    public let widthMarker: Int?
    public let initialMessage: String?

    public init(minimumMessageLength: Int?, widthMarker: Int?, initialMessage: String?) {
        self.minimumMessageLength = minimumMessageLength
        self.widthMarker = widthMarker
        self.initialMessage = initialMessage
    }
}

public struct LockProjectProperties: Equatable, Sendable {
    public let minimumMessageLength: Int?
    public let initialMessage: String?

    public init(minimumMessageLength: Int?, initialMessage: String?) {
        self.minimumMessageLength = minimumMessageLength
        self.initialMessage = initialMessage
    }
}

public struct BugtraqProjectProperties: Equatable, Sendable {
    public let urlTemplate: String?
    public let messageTemplate: String?
    public let numericInputOnly: Bool
    public let appendMessage: Bool
    public let regexPatterns: [String]
    public let repositoryRoot: String?

    private static let issueIdentifierAllowedCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    public init(
        urlTemplate: String?,
        messageTemplate: String?,
        numericInputOnly: Bool,
        appendMessage: Bool,
        regexPatterns: [String],
        repositoryRoot: String?
    ) {
        self.urlTemplate = urlTemplate
        self.messageTemplate = messageTemplate
        self.numericInputOnly = numericInputOnly
        self.appendMessage = appendMessage
        self.regexPatterns = regexPatterns
        self.repositoryRoot = repositoryRoot
    }

    /// Regex 模式优先于输入框模式，与 TortoiseSVN 一致。
    public var usesRegexMode: Bool { !regexPatterns.isEmpty }
    public var usesInputMode: Bool {
        !usesRegexMode && messageTemplate?.contains("%BUGID%") == true
    }

    public func applyingIssueInput(_ input: String, to message: String) -> String? {
        guard usesInputMode, let messageTemplate else { return nil }
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, isValidIssueInput(normalized) else { return nil }

        let issueLine = messageTemplate.replacingOccurrences(of: "%BUGID%", with: normalized)
        let existing = message.trimmingCharacters(in: .newlines)
        guard !existing.isEmpty else { return issueLine }
        return appendMessage ? "\(existing)\n\(issueLine)" : "\(issueLine)\n\(existing)"
    }

    public func issueReferences(in message: String) -> [BugtraqIssueReference] {
        guard usesRegexMode else { return [] }
        let identifiers: [String]
        switch regexPatterns.count {
        case 1:
            identifiers = captureGroups(using: regexPatterns[0], in: message)
        case 2:
            identifiers = matches(using: regexPatterns[0], in: message)
                .flatMap { captureGroups(using: regexPatterns[1], in: $0) }
        default:
            return []
        }

        var seen = Set<String>()
        return identifiers.compactMap { identifier in
            let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return BugtraqIssueReference(identifier: trimmed, url: issueURL(for: trimmed))
        }
    }

    private func isValidIssueInput(_ input: String) -> Bool {
        guard numericInputOnly else { return true }
        let identifiers = input.split(separator: ",", omittingEmptySubsequences: false)
        guard !identifiers.isEmpty else { return false }
        return identifiers.allSatisfy { part in
            let identifier = part.trimmingCharacters(in: .whitespacesAndNewlines)
            return !identifier.isEmpty && identifier.allSatisfy(\.isNumber)
        }
    }

    private func issueURL(for identifier: String) -> String? {
        guard let urlTemplate else { return nil }
        let encoded = identifier.addingPercentEncoding(
            withAllowedCharacters: Self.issueIdentifierAllowedCharacters
        ) ?? identifier
        let expanded: String
        if urlTemplate.hasPrefix("^/") {
            guard let repositoryRoot else { return nil }
            expanded = repositoryRoot.trimmingCharacters(in: .whitespacesAndNewlines).trimmingTrailingSlashes()
                + "/"
                + String(urlTemplate.dropFirst(2))
        } else {
            expanded = urlTemplate
        }
        return expanded.replacingOccurrences(of: "%BUGID%", with: encoded)
    }

    private func captureGroups(using pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).flatMap { match -> [String] in
            guard match.numberOfRanges > 1 else { return [] }
            return (1..<match.numberOfRanges).compactMap { index in
                guard let range = Range(match.range(at: index), in: text) else { return nil }
                return String(text[range])
            }
        }
    }

    private func matches(using pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }
}

private extension String {
    func trimmingTrailingSlashes() -> String {
        var result = self
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}

/// 解析工作副本目录上的 `tsvn:*` 与 `bugtraq:*` 属性。
public struct ProjectPropertyPolicy: Equatable, Sendable {
    public let commit: CommitProjectProperties
    public let lock: LockProjectProperties
    public let logTemplates: ProjectLogTemplates
    public let bugtraq: BugtraqProjectProperties
    public let projectLanguage: String?
    public let diagnostics: [ProjectPropertyDiagnostic]

    public init(propertySets: [[SvnProperty]], repositoryRoot: String? = nil) {
        let mergedProperties = propertySets.reduce(into: [String: SvnProperty]()) { merged, properties in
            for property in properties {
                merged[property.name] = property
            }
        }
        self.init(properties: Array(mergedProperties.values), repositoryRoot: repositoryRoot)
    }

    public init(properties: [SvnProperty], repositoryRoot: String? = nil) {
        let values = properties.reduce(into: [String: String]()) { result, property in
            result[property.name] = property.value
        }
        var diagnostics: [ProjectPropertyDiagnostic] = []
        let commitMinimum = Self.nonNegativeInteger(
            named: "tsvn:logminsize",
            values: values,
            diagnostics: &diagnostics
        )
        let widthMarker = Self.nonNegativeInteger(
            named: "tsvn:logwidthmarker",
            values: values,
            diagnostics: &diagnostics
        )
        let lockMinimum = Self.nonNegativeInteger(
            named: "tsvn:lockmsgminsize",
            values: values,
            diagnostics: &diagnostics
        )
        let numericInputOnly = Self.boolean(
            named: "bugtraq:number",
            values: values,
            defaultValue: true,
            diagnostics: &diagnostics
        )
        let appendMessage = Self.boolean(
            named: "bugtraq:append",
            values: values,
            defaultValue: false,
            diagnostics: &diagnostics
        )
        let regexPatterns = Self.regexPatterns(values["bugtraq:logregex"], diagnostics: &diagnostics)
        let messageTemplate = Self.nonEmpty(values["bugtraq:message"])
        if let messageTemplate, !messageTemplate.contains("%BUGID%") {
            diagnostics.append(.bugtraqMessageMissingPlaceholder)
        }
        let genericLogTemplate = Self.nonEmpty(values["tsvn:logtemplate"])
        let operationTemplates = Dictionary(
            uniqueKeysWithValues: ProjectLogTemplateOperation.allCases.compactMap { operation in
                Self.nonEmpty(values[operation.propertyName]).map { (operation, $0) }
            }
        )
        let logTemplates = ProjectLogTemplates(
            generic: genericLogTemplate,
            operationSpecific: operationTemplates
        )
        let bugtraqURL = Self.nonEmpty(values["bugtraq:url"])
        if bugtraqURL?.hasPrefix("^/") == true, repositoryRoot == nil {
            diagnostics.append(.bugtraqRepositoryRootUnavailable)
        }

        commit = CommitProjectProperties(
            minimumMessageLength: commitMinimum,
            widthMarker: widthMarker,
            initialMessage: logTemplates.initialMessage(for: .commit)
        )
        lock = LockProjectProperties(
            minimumMessageLength: lockMinimum,
            initialMessage: logTemplates.initialMessage(for: .lock)
        )
        self.logTemplates = logTemplates
        bugtraq = BugtraqProjectProperties(
            urlTemplate: bugtraqURL,
            messageTemplate: messageTemplate,
            numericInputOnly: numericInputOnly,
            appendMessage: appendMessage,
            regexPatterns: regexPatterns,
            repositoryRoot: repositoryRoot
        )
        projectLanguage = Self.nonEmpty(values["tsvn:projectlanguage"])
        self.diagnostics = diagnostics
    }

    /// 多选路径没有共同的最近项目目录时，强制约束取最严格值；
    /// 无法用一条提交说明同时表达的模板或 Bugtraq 配置则显式禁用，避免任意选一路径。
    public static func combining(_ policies: [ProjectPropertyPolicy]) -> ProjectPropertyPolicy {
        guard let first = policies.first else {
            return ProjectPropertyPolicy(properties: [])
        }
        guard policies.count > 1 else { return first }

        var diagnostics = policies.flatMap(\.diagnostics).reduce(into: [ProjectPropertyDiagnostic]()) { result, diagnostic in
            if !result.contains(diagnostic) {
                result.append(diagnostic)
            }
        }

        let projectLanguages = policies.map(\.projectLanguage)
        let bugtraqProperties = policies.map(\.bugtraq)

        let genericTemplates = policies.map(\.logTemplates.generic)
        let genericTemplate = consistentOptionalValue(genericTemplates)
        var operationTemplates: [ProjectLogTemplateOperation: String] = [:]
        for operation in ProjectLogTemplateOperation.allCases {
            let templates = policies.map { $0.logTemplates.specificTemplate(for: operation) }
            if let template = consistentOptionalValue(templates) {
                operationTemplates[operation] = template
            }
            appendConflict(operation.propertyName, when: !allValuesMatch(templates), to: &diagnostics)
        }
        let logTemplates = ProjectLogTemplates(generic: genericTemplate, operationSpecific: operationTemplates)
        let projectLanguage = consistentOptionalValue(projectLanguages)
        let bugtraq = consistentValue(bugtraqProperties) ?? BugtraqProjectProperties(
            urlTemplate: nil,
            messageTemplate: nil,
            numericInputOnly: true,
            appendMessage: false,
            regexPatterns: [],
            repositoryRoot: first.bugtraq.repositoryRoot
        )

        appendConflict("tsvn:logtemplate", when: !allValuesMatch(genericTemplates), to: &diagnostics)
        appendConflict("tsvn:projectlanguage", when: !allValuesMatch(projectLanguages), to: &diagnostics)
        appendConflict("bugtraq:*", when: !allValuesMatch(bugtraqProperties), to: &diagnostics)

        return ProjectPropertyPolicy(
            commit: CommitProjectProperties(
                minimumMessageLength: policies.compactMap(\.commit.minimumMessageLength).max(),
                widthMarker: policies.compactMap(\.commit.widthMarker).min(),
                initialMessage: logTemplates.initialMessage(for: .commit)
            ),
            lock: LockProjectProperties(
                minimumMessageLength: policies.compactMap(\.lock.minimumMessageLength).max(),
                initialMessage: logTemplates.initialMessage(for: .lock)
            ),
            logTemplates: logTemplates,
            bugtraq: bugtraq,
            projectLanguage: projectLanguage,
            diagnostics: diagnostics
        )
    }

    private init(
        commit: CommitProjectProperties,
        lock: LockProjectProperties,
        logTemplates: ProjectLogTemplates,
        bugtraq: BugtraqProjectProperties,
        projectLanguage: String?,
        diagnostics: [ProjectPropertyDiagnostic]
    ) {
        self.commit = commit
        self.lock = lock
        self.logTemplates = logTemplates
        self.bugtraq = bugtraq
        self.projectLanguage = projectLanguage
        self.diagnostics = diagnostics
    }

    public func initialMessage(for operation: ProjectLogTemplateOperation) -> String? {
        switch operation {
        case .commit:
            return commit.initialMessage
        case .lock:
            return lock.initialMessage
        default:
            return logTemplates.initialMessage(for: operation)
        }
    }

    private static func consistentValue<T: Equatable>(_ values: [T]) -> T? {
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private static func consistentOptionalValue<T: Equatable>(_ values: [T?]) -> T? {
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    private static func allValuesMatch<T: Equatable>(_ values: [T]) -> Bool {
        guard let first = values.first else { return true }
        return values.allSatisfy { $0 == first }
    }

    private static func appendConflict(
        _ name: String,
        when conflicts: Bool,
        to diagnostics: inout [ProjectPropertyDiagnostic]
    ) {
        let diagnostic = ProjectPropertyDiagnostic.conflictingProjectProperty(name)
        if conflicts, !diagnostics.contains(diagnostic) {
            diagnostics.append(diagnostic)
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static func nonNegativeInteger(
        named name: String,
        values: [String: String],
        diagnostics: inout [ProjectPropertyDiagnostic]
    ) -> Int? {
        guard let raw = values[name] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value >= 0 else {
            diagnostics.append(.invalidNonNegativeInteger(name: name, value: raw))
            return nil
        }
        return value == 0 ? nil : value
    }

    private static func boolean(
        named name: String,
        values: [String: String],
        defaultValue: Bool,
        diagnostics: inout [ProjectPropertyDiagnostic]
    ) -> Bool {
        guard let raw = values[name] else { return defaultValue }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default:
            diagnostics.append(.invalidBoolean(name: name, value: raw))
            return defaultValue
        }
    }

    private static func regexPatterns(
        _ value: String?,
        diagnostics: inout [ProjectPropertyDiagnostic]
    ) -> [String] {
        guard let value = nonEmpty(value) else { return [] }
        let patterns = value
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard patterns.count == 1 || patterns.count == 2 else {
            diagnostics.append(.invalidBugtraqRegexLineCount(patterns.count))
            return []
        }
        guard patterns.allSatisfy({ (try? NSRegularExpression(pattern: $0)) != nil }) else {
            diagnostics.append(.invalidBugtraqRegex(value: value))
            return []
        }
        return patterns
    }
}

public enum CommitMessagePolicy {
    public static func validationError(
        for message: String,
        properties: ProjectPropertyPolicy
    ) -> ProjectMessageValidationError? {
        guard let minimum = properties.commit.minimumMessageLength else { return nil }
        let actual = message.count
        guard actual < minimum else { return nil }
        return .belowMinimumLength(required: minimum, actual: actual)
    }

    /// 宽度标记仅提示，TortoiseSVN 同样不会因超宽阻止提交。
    public static func overlongLineNumbers(in message: String, properties: ProjectPropertyPolicy) -> [Int] {
        guard let width = properties.commit.widthMarker else { return [] }
        return message.components(separatedBy: .newlines).enumerated().compactMap { offset, line in
            line.count > width ? offset + 1 : nil
        }
    }
}

public enum LockMessagePolicy {
    public static func validationError(
        for message: String?,
        properties: ProjectPropertyPolicy
    ) -> ProjectMessageValidationError? {
        guard let minimum = properties.lock.minimumMessageLength else { return nil }
        let actual = message?.count ?? 0
        guard actual < minimum else { return nil }
        return .belowMinimumLength(required: minimum, actual: actual)
    }
}
