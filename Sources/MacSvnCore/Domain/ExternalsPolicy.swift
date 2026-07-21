import Foundation

public struct SvnExternalDefinition: Identifiable, Equatable, Sendable {
    public var revision: Revision?
    public var url: String
    public var pegRevision: Revision?
    public var localPath: String

    public var id: String { "\(url)|\(localPath)" }

    public init(
        revision: Revision? = nil,
        url: String,
        pegRevision: Revision? = nil,
        localPath: String
    ) {
        self.revision = revision
        self.url = url
        self.pegRevision = pegRevision
        self.localPath = localPath
    }
}

public enum SvnExternalsError: Error, Equatable, LocalizedError {
    case invalidLine(number: Int, detail: String)
    case invalidLocalPath(String)

    public var errorDescription: String? {
        switch self {
        case .invalidLine(let number, let detail): "外部定义第 \(number) 行无效：\(detail)"
        case .invalidLocalPath(let path): "外部定义本地路径无效：\(path)"
        }
    }
}

public enum SvnExternalDocumentLine: Equatable, Sendable {
    case blank(String)
    case comment(String)
    case definition(SvnExternalDefinition)
}

public struct SvnExternalsDocument: Equatable, Sendable {
    public var lines: [SvnExternalDocumentLine]

    public init(text: String) throws {
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var parsed: [SvnExternalDocumentLine] = []
        for (offset, rawLine) in rawLines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                parsed.append(.blank(rawLine))
            } else if trimmed.hasPrefix("#") {
                parsed.append(.comment(rawLine))
            } else {
                parsed.append(.definition(try SvnExternalsPolicy.parseDefinition(
                    rawLine,
                    lineNumber: offset + 1
                )))
            }
        }
        self.lines = parsed
    }

    public init(definitions: [SvnExternalDefinition]) {
        self.lines = definitions.map(SvnExternalDocumentLine.definition)
    }

    public var definitions: [SvnExternalDefinition] {
        lines.compactMap {
            guard case .definition(let value) = $0 else { return nil }
            return value
        }
    }

    public func replacing(definitions: [SvnExternalDefinition]) -> SvnExternalsDocument {
        var remaining = definitions[...]
        var replaced: [SvnExternalDocumentLine] = []
        for line in lines {
            if case .definition = line {
                if let next = remaining.first {
                    replaced.append(.definition(next))
                    remaining = remaining.dropFirst()
                }
            } else {
                replaced.append(line)
            }
        }
        replaced.append(contentsOf: remaining.map(SvnExternalDocumentLine.definition))
        var document = self
        document.lines = replaced
        return document
    }

    public func render() -> String {
        lines.map { line in
            switch line {
            case .blank(let raw), .comment(let raw): raw
            case .definition(let definition): SvnExternalsPolicy.render(definition)
            }
        }.joined(separator: "\n")
    }
}

public enum SvnExternalsPolicy: Sendable {
    public static func validateLocalPath(_ value: String) throws -> String {
        let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !components.contains(where: { $0 == ".." }) else {
            throw SvnExternalsError.invalidLocalPath(path)
        }
        return path
    }

    public static func targetURL(workingCopy: URL, path: String) -> URL {
        let target = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if (target as NSString).isAbsolutePath {
            return URL(fileURLWithPath: target).standardizedFileURL
        }
        if target == "." || target.isEmpty {
            return workingCopy.standardizedFileURL
        }
        return workingCopy.appendingPathComponent(target).standardizedFileURL
    }

    static func parseDefinition(_ line: String, lineNumber: Int) throws -> SvnExternalDefinition {
        let tokens = try tokenize(line, lineNumber: lineNumber)
        var revision: Revision?
        var legacyPegRevision: Revision?
        let urlToken: String
        let localPath: String

        if let parsedRevision = revisionPrefix(tokens) {
            revision = Revision(parsedRevision.value)
            urlToken = tokens[parsedRevision.nextIndex]
            localPath = tokens[parsedRevision.nextIndex + 1]
            guard tokens.count == parsedRevision.nextIndex + 2 else {
                throw SvnExternalsError.invalidLine(number: lineNumber, detail: "参数数量不正确")
            }
        } else if let oldRevision = oldSyntaxRevision(tokens) {
            legacyPegRevision = Revision(oldRevision.value)
            localPath = tokens[0]
            urlToken = tokens[oldRevision.urlIndex]
        } else {
            guard !tokens.prefix(2).contains(where: isRevisionOption) else {
                throw SvnExternalsError.invalidLine(number: lineNumber, detail: "修订参数不完整")
            }
            guard tokens.count == 2 else {
                throw SvnExternalsError.invalidLine(number: lineNumber, detail: "需要 URL 和本地路径")
            }
            if !looksLikeURL(tokens[0]), looksLikeURL(tokens[1]) {
                localPath = tokens[0]
                urlToken = tokens[1]
            } else {
                // 两个相对路径的歧义格式由 SVN 解释为 relative URL + local path。
                urlToken = tokens[0]
                localPath = tokens[1]
            }
        }

        guard !urlToken.isEmpty, !urlToken.contains(where: \.isWhitespace) else {
            throw SvnExternalsError.invalidLine(number: lineNumber, detail: "URL 无效")
        }
        let split = splitPegRevision(urlToken)
        guard legacyPegRevision == nil || split.revision == nil else {
            throw SvnExternalsError.invalidLine(number: lineNumber, detail: "peg revision 重复")
        }
        return SvnExternalDefinition(
            revision: revision,
            url: split.url,
            pegRevision: split.revision ?? legacyPegRevision,
            localPath: try validateLocalPath(localPath)
        )
    }

    public static func render(_ definition: SvnExternalDefinition) -> String {
        var parts: [String] = []
        if let revision = definition.revision {
            parts += ["-r", revision.description]
        }
        let url = definition.pegRevision.map { "\(definition.url)@\($0.value)" } ?? definition.url
        parts.append(url)
        parts.append(quoteIfNeeded(definition.localPath))
        return parts.joined(separator: " ")
    }

    private static func revisionPrefix(_ tokens: [String]) -> (value: Int, nextIndex: Int)? {
        guard let first = tokens.first else { return nil }
        if first == "-r", tokens.count >= 4, let value = Int(tokens[1]), value >= 0 {
            return (value, 2)
        }
        if first.hasPrefix("-r"), let value = Int(first.dropFirst(2)), value >= 0, tokens.count >= 3 {
            return (value, 1)
        }
        return nil
    }

    private static func oldSyntaxRevision(_ tokens: [String]) -> (value: Int, urlIndex: Int)? {
        guard tokens.count >= 3 else { return nil }
        if tokens[1] == "-r", tokens.count == 4, let value = Int(tokens[2]), value >= 0 {
            return (value, 3)
        }
        if tokens[1].hasPrefix("-r"), tokens.count == 3,
           let value = Int(tokens[1].dropFirst(2)), value >= 0 {
            return (value, 2)
        }
        return nil
    }

    private static func isRevisionOption(_ value: String) -> Bool {
        guard value.hasPrefix("-r") else { return false }
        let suffix = value.dropFirst(2)
        return suffix.isEmpty || suffix.allSatisfy(\.isNumber)
    }

    private static func splitPegRevision(_ value: String) -> (url: String, revision: Revision?) {
        guard let marker = value.lastIndex(of: "@"), marker < value.index(before: value.endIndex),
              let revision = Int(value[value.index(after: marker)...]), revision >= 0 else {
            return (value, nil)
        }
        return (String(value[..<marker]), Revision(revision))
    }

    private static func looksLikeURL(_ value: String) -> Bool {
        value.contains("://") || value.hasPrefix("^") || value.hasPrefix("../")
            || value.hasPrefix("//") || value.hasPrefix("/")
    }

    private static func quoteIfNeeded(_ value: String) -> String {
        guard value.contains(where: \.isWhitespace) else { return value }
        return "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func tokenize(_ line: String, lineNumber: Int) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false
        for character in line {
            if escaping {
                current.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if let activeQuote = quote {
                if character == activeQuote { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        guard quote == nil else {
            throw SvnExternalsError.invalidLine(number: lineNumber, detail: "引号未闭合")
        }
        if escaping { current.append("\\") }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
