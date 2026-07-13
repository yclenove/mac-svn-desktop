import Foundation

public enum FinderSyncInfoXMLParser {
    public static func parseDepths(_ data: Data) throws -> [String: SvnDepth] {
        let delegate = FinderSyncInfoXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let detail = parser.parserError?.localizedDescription ?? "Unable to parse Finder Sync info XML."
            throw SvnError.parse(detail: detail)
        }
        return delegate.depths
    }
}

private final class FinderSyncInfoXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var depths: [String: SvnDepth] = [:]
    private var currentPath: String?
    private var insideWorkingCopyInfo = false
    private var collectingDepth = false
    private var currentText = ""

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
            currentPath = attributeDict["path"]
        case "wc-info":
            insideWorkingCopyInfo = true
        case "depth" where insideWorkingCopyInfo:
            collectingDepth = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingDepth {
            currentText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "depth" where collectingDepth:
            if let currentPath,
               let depth = SvnDepth(rawValue: currentText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                depths[currentPath] = depth
            }
            collectingDepth = false
        case "wc-info":
            insideWorkingCopyInfo = false
        case "entry":
            currentPath = nil
        default:
            break
        }
        currentText = ""
    }
}
