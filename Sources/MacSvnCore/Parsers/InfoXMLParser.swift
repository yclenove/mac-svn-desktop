import Foundation

public enum InfoXMLParser {
    public static func parse(_ data: Data) throws -> SvnInfo {
        let delegate = InfoXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let detail = parser.parserError?.localizedDescription ?? "Unable to parse svn info XML."
            throw SvnError.parse(detail: detail)
        }

        guard let info = delegate.info else {
            throw SvnError.parse(detail: "Unable to find entry in svn info XML.")
        }

        return info
    }
}

private final class InfoXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var info: SvnInfo?

    private var currentPath = ""
    private var currentURL = ""
    private var currentRepositoryRoot: String?
    private var currentRevision: Revision?
    private var currentKind: String?
    private var currentConflicts: [ConflictInfo] = []
    private var currentLastChangedRevision: Revision?
    private var currentLastChangedAuthor: String?
    private var currentLastChangedDate: Date?
    private var currentLockToken: String?
    private var currentLockOwner: String?
    private var currentLockComment: String?
    private var currentLockCreated: Date?
    private var isCollectingTextConflict = false
    private var currentConflictBaseFile: String?
    private var currentConflictMineFile: String?
    private var currentConflictTheirsFile: String?
    private var currentText = ""
    private var elementStack: [String] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        elementStack.append(elementName)
        currentText = ""

        guard info == nil else {
            return
        }

        switch elementName {
        case "entry":
            currentPath = attributeDict["path"] ?? ""
            currentRevision = attributeDict["revision"].flatMap(Int.init).map { Revision($0) }
            currentKind = attributeDict["kind"]
            currentURL = ""
            currentRepositoryRoot = nil
            currentConflicts = []
            currentLastChangedRevision = nil
            currentLastChangedAuthor = nil
            currentLastChangedDate = nil
            currentLockToken = nil
            currentLockOwner = nil
            currentLockComment = nil
            currentLockCreated = nil
        case "commit":
            currentLastChangedRevision = attributeDict["revision"].flatMap(Int.init).map { Revision($0) }
        case "conflict":
            isCollectingTextConflict = true
            currentConflictBaseFile = nil
            currentConflictMineFile = nil
            currentConflictTheirsFile = nil
        case "tree-conflict":
            currentConflicts.append(ConflictInfo(
                path: attributeDict["victim"] ?? currentPath,
                kind: .tree,
                baseFile: nil,
                mineFile: nil,
                theirsFile: nil,
                treeConflict: TreeConflictDetails(
                    operation: attributeDict["operation"],
                    action: attributeDict["action"],
                    reason: attributeDict["reason"]
                )
            ))
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
        let trimmedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "url" where info == nil:
            currentURL = trimmedText
        case "root" where elementStack.suffix(2) == ["repository", "root"] && info == nil:
            currentRepositoryRoot = trimmedText
        case "author" where elementStack.suffix(2) == ["commit", "author"] && info == nil:
            currentLastChangedAuthor = trimmedText
        case "date" where elementStack.suffix(2) == ["commit", "date"] && info == nil:
            currentLastChangedDate = Self.parseDate(trimmedText)
        case "token" where elementStack.suffix(2) == ["lock", "token"] && info == nil:
            currentLockToken = trimmedText
        case "owner" where elementStack.suffix(2) == ["lock", "owner"] && info == nil:
            currentLockOwner = trimmedText
        case "comment" where elementStack.suffix(2) == ["lock", "comment"] && info == nil:
            currentLockComment = trimmedText
        case "created" where elementStack.suffix(2) == ["lock", "created"] && info == nil:
            currentLockCreated = Self.parseDate(trimmedText)
        case "prev-base-file" where isCollectingTextConflict && info == nil:
            currentConflictBaseFile = trimmedText
        case "prev-wc-file" where isCollectingTextConflict && info == nil:
            currentConflictMineFile = trimmedText
        case "cur-base-file" where isCollectingTextConflict && info == nil:
            currentConflictTheirsFile = trimmedText
        case "conflict" where info == nil:
            currentConflicts.append(ConflictInfo(
                path: currentPath,
                kind: .text,
                baseFile: currentConflictBaseFile,
                mineFile: currentConflictMineFile,
                theirsFile: currentConflictTheirsFile,
                treeConflict: nil
            ))
            isCollectingTextConflict = false
        case "entry" where info == nil:
            info = SvnInfo(
                path: currentPath,
                url: currentURL,
                repositoryRoot: currentRepositoryRoot,
                revision: currentRevision,
                kind: currentKind,
                conflicts: currentConflicts,
                lastChangedRevision: currentLastChangedRevision,
                lastChangedAuthor: currentLastChangedAuthor,
                lastChangedDate: currentLastChangedDate,
                lock: lockInfo
            )
        default:
            break
        }

        currentText = ""
        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
    }

    private var lockInfo: RemoteLockInfo? {
        guard currentLockToken != nil || currentLockOwner != nil
                || currentLockComment != nil || currentLockCreated != nil else {
            return nil
        }
        return RemoteLockInfo(
            token: currentLockToken,
            owner: currentLockOwner,
            comment: currentLockComment,
            created: currentLockCreated
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
