import Foundation

public enum LockStatusXMLParser {
    public static func parse(_ data: Data) throws -> [SvnLock] {
        let delegate = LockStatusXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let detail = parser.parserError?.localizedDescription ?? "Unable to parse svn lock status XML."
            throw SvnError.parse(detail: detail)
        }

        return delegate.locks
    }
}

private final class LockStatusXMLParserDelegate: NSObject, XMLParserDelegate {
    private enum StatusScope {
        case workingCopy
        case repository
    }

    private struct ParsedLock {
        var token: String?
        var owner: String?
        var comment: String?
        var created: Date?
    }

    private(set) var locks: [SvnLock] = []

    private var currentEntryPath: String?
    private var currentScope: StatusScope?
    private var currentElement: String?
    private var currentText = ""
    private var parsedLock: ParsedLock?
    private var workingCopyLock: ParsedLock?
    private var repositoryLock: ParsedLock?

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
            currentEntryPath = attributeDict["path"]
            workingCopyLock = nil
            repositoryLock = nil
        case "wc-status":
            currentScope = .workingCopy
        case "repos-status":
            currentScope = .repository
        case "lock":
            parsedLock = ParsedLock()
        case "token", "owner", "comment", "created":
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

        if parsedLock != nil, currentElement == elementName {
            switch elementName {
            case "token":
                parsedLock?.token = text.isEmpty ? nil : text
            case "owner":
                parsedLock?.owner = text.isEmpty ? nil : text
            case "comment":
                parsedLock?.comment = text.isEmpty ? nil : text
            case "created":
                parsedLock?.created = dateFormatter.date(from: text)
            default:
                break
            }
            currentElement = nil
        }

        switch elementName {
        case "lock":
            if let parsedLock {
                switch currentScope {
                case .workingCopy:
                    workingCopyLock = parsedLock
                case .repository:
                    repositoryLock = parsedLock
                case nil:
                    break
                }
            }
            parsedLock = nil
        case "wc-status", "repos-status":
            currentScope = nil
        case "entry":
            appendLockForCurrentEntry()
            currentEntryPath = nil
            workingCopyLock = nil
            repositoryLock = nil
        default:
            break
        }

        currentText = ""
    }

    private func appendLockForCurrentEntry() {
        guard let currentEntryPath, workingCopyLock != nil || repositoryLock != nil else {
            return
        }

        let lock = repositoryLock ?? workingCopyLock
        locks.append(SvnLock(
            target: currentEntryPath,
            token: lock?.token,
            owner: lock?.owner,
            comment: lock?.comment,
            created: lock?.created,
            isOwnedByWorkingCopy: workingCopyLock != nil,
            isRepositoryLocked: repositoryLock != nil
        ))
    }
}
