import Foundation

public enum LogXMLParser {
    public static func parse(_ data: Data) throws -> [LogEntry] {
        let delegate = LogXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let detail = parser.parserError?.localizedDescription ?? "Unable to parse svn log XML."
            throw SvnError.parse(detail: detail)
        }

        return delegate.entries
    }
}

private final class LogXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var entries: [LogEntry] = []

    private var currentRevision: Revision?
    private var currentAuthor = ""
    private var currentDate: Date?
    private var currentMessage = ""
    private var currentChangedPaths: [ChangedPath] = []
    private var currentPathAttributes: [String: String] = [:]
    private var currentText = ""
    private var currentElement: String?

    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "logentry":
            currentRevision = attributeDict["revision"].flatMap(Int.init).map { Revision($0) }
            currentAuthor = ""
            currentDate = nil
            currentMessage = ""
            currentChangedPaths = []
        case "path":
            currentPathAttributes = attributeDict
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
        switch elementName {
        case "author":
            currentAuthor = currentText
        case "date":
            currentDate = dateFormatter.date(from: currentText)
        case "msg":
            currentMessage = currentText
        case "path":
            currentChangedPaths.append(ChangedPath(
                path: currentText,
                action: ChangedPathAction(rawSvnAction: currentPathAttributes["action"]),
                kind: currentPathAttributes["kind"],
                copyFromPath: currentPathAttributes["copyfrom-path"],
                copyFromRevision: currentPathAttributes["copyfrom-rev"].flatMap(Int.init).map { Revision($0) }
            ))
            currentPathAttributes = [:]
        case "logentry":
            if let currentRevision {
                entries.append(LogEntry(
                    revision: currentRevision,
                    author: currentAuthor,
                    date: currentDate,
                    message: currentMessage,
                    changedPaths: currentChangedPaths
                ))
            }
            currentRevision = nil
            currentChangedPaths = []
        default:
            break
        }

        currentText = ""
        currentElement = nil
    }
}
