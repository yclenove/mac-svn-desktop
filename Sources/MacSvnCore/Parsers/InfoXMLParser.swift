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

        guard elementName == "entry", info == nil else {
            return
        }

        currentPath = attributeDict["path"] ?? ""
        currentRevision = attributeDict["revision"].flatMap(Int.init).map { Revision($0) }
        currentKind = attributeDict["kind"]
        currentURL = ""
        currentRepositoryRoot = nil
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
        case "entry" where info == nil:
            info = SvnInfo(
                path: currentPath,
                url: currentURL,
                repositoryRoot: currentRepositoryRoot,
                revision: currentRevision,
                kind: currentKind
            )
        default:
            break
        }

        currentText = ""
        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
    }
}
