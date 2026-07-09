import Foundation

public extension ISO8601DateFormatter {
    static var svnXML: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

public enum ListXMLParser {
    public static func parse(_ data: Data) throws -> [RemoteEntry] {
        let delegate = ListXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let detail = parser.parserError?.localizedDescription ?? "Unable to parse svn list XML."
            throw SvnError.parse(detail: detail)
        }

        return delegate.entries
    }
}

private final class ListXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var entries: [RemoteEntry] = []

    private var currentKind: RemoteEntryKind?
    private var currentName = ""
    private var currentSize: Int?
    private var currentRevision: Revision?
    private var currentAuthor: String?
    private var currentDate: Date?
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
            currentKind = RemoteEntryKind(rawSvnKind: attributeDict["kind"])
            currentName = ""
            currentSize = nil
            currentRevision = nil
            currentAuthor = nil
            currentDate = nil
        case "commit":
            currentRevision = attributeDict["revision"].flatMap(Int.init).map { Revision($0) }
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

        switch elementName {
        case "name":
            currentName = text
        case "size":
            currentSize = Int(text)
        case "author":
            currentAuthor = text.isEmpty ? nil : text
        case "date":
            currentDate = dateFormatter.date(from: text)
        case "entry":
            if let currentKind {
                entries.append(RemoteEntry(
                    name: currentName,
                    path: currentName,
                    kind: currentKind,
                    size: currentSize,
                    revision: currentRevision,
                    author: currentAuthor,
                    date: currentDate
                ))
            }
            currentKind = nil
        default:
            break
        }

        currentText = ""
    }
}
