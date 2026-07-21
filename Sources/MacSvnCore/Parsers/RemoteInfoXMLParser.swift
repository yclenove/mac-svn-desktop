import Foundation

public enum RemoteInfoXMLParser {
    public static func parseDirectoryEntries(_ data: Data, targetURL: String) throws -> [RemoteEntry] {
        let delegate = RemoteInfoXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let detail = parser.parserError?.localizedDescription ?? "Unable to parse remote svn info XML."
            throw SvnError.parse(detail: detail)
        }

        let normalizedTarget = normalize(url: targetURL)
        return delegate.entries.compactMap { parsed in
            guard normalize(url: parsed.url) != normalizedTarget else {
                return nil
            }
            return parsed.entry
        }
    }

    private static func normalize(url: String) -> String {
        let withoutPeg = LogContextActionPolicy.stripPegRevision(from: url)
        return withoutPeg.hasSuffix("/") ? String(withoutPeg.dropLast()) : withoutPeg
    }
}

private struct ParsedRemoteInfoEntry {
    let url: String
    let entry: RemoteEntry
}

private final class RemoteInfoXMLParserDelegate: NSObject, XMLParserDelegate {
    private struct ParsedLock {
        var token: String?
        var owner: String?
        var comment: String?
        var created: Date?
    }

    private(set) var entries: [ParsedRemoteInfoEntry] = []

    private var entryPath = ""
    private var entryKind: RemoteEntryKind?
    private var entrySize: Int?
    private var entryRevision: Revision?
    private var entryURL = ""
    private var entryAuthor: String?
    private var entryDate: Date?
    private var entryLock: ParsedLock?
    private var isInsideLock = false
    private var currentElement: String?
    private var currentText = ""

    private let dateFormatter = ISO8601DateFormatter.svnXML

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""

        switch elementName {
        case "entry":
            entryPath = attributeDict["path"] ?? ""
            entryKind = RemoteEntryKind(rawSvnKind: attributeDict["kind"])
            entrySize = attributeDict["size"].flatMap(Int.init)
            entryRevision = attributeDict["revision"].flatMap(Int.init).map { Revision($0) }
            entryURL = ""
            entryAuthor = nil
            entryDate = nil
            entryLock = nil
        case "commit":
            if let revision = attributeDict["revision"].flatMap(Int.init) {
                entryRevision = Revision(revision)
            }
        case "lock":
            isInsideLock = true
            entryLock = ParsedLock()
        case "url", "author", "date", "token", "owner", "comment", "created":
            currentElement = elementName
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if currentElement == elementName {
            switch elementName {
            case "url":
                entryURL = text
            case "author":
                entryAuthor = text.isEmpty ? nil : text
            case "date":
                entryDate = dateFormatter.date(from: text)
            case "token" where isInsideLock:
                entryLock?.token = text.isEmpty ? nil : text
            case "owner" where isInsideLock:
                entryLock?.owner = text.isEmpty ? nil : text
            case "comment" where isInsideLock:
                entryLock?.comment = text.isEmpty ? nil : text
            case "created" where isInsideLock:
                entryLock?.created = dateFormatter.date(from: text)
            default:
                break
            }
            currentElement = nil
        }

        switch elementName {
        case "lock":
            isInsideLock = false
        case "entry":
            appendCurrentEntry()
            entryKind = nil
        default:
            break
        }

        currentText = ""
    }

    private func appendCurrentEntry() {
        guard let entryKind, !entryURL.isEmpty else {
            return
        }

        let urlName = URL(string: entryURL)?.lastPathComponent.removingPercentEncoding
        let pathName = URL(fileURLWithPath: entryPath).lastPathComponent
        let name = (urlName?.isEmpty == false ? urlName : nil) ?? pathName
        let lock = entryLock.map {
            RemoteLockInfo(token: $0.token, owner: $0.owner, comment: $0.comment, created: $0.created)
        }
        entries.append(ParsedRemoteInfoEntry(
            url: entryURL,
            entry: RemoteEntry(
                name: name,
                path: name,
                kind: entryKind,
                size: entrySize,
                revision: entryRevision,
                author: entryAuthor,
                date: entryDate,
                lock: lock
            )
        ))
    }
}
