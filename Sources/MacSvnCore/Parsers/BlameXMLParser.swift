import Foundation

public enum BlameXMLParser {
    public static func parse(_ data: Data) throws -> [BlameLine] {
        let delegate = BlameXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let detail = parser.parserError?.localizedDescription ?? "Unable to parse svn blame XML."
            throw SvnError.parse(detail: detail)
        }

        return delegate.lines
    }
}

private final class BlameXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var lines: [BlameLine] = []

    private var currentLineNumber: Int?
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
            currentLineNumber = attributeDict["line-number"].flatMap(Int.init)
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
        case "author":
            currentAuthor = text.isEmpty ? nil : text
        case "date":
            currentDate = dateFormatter.date(from: text)
        case "entry":
            if let currentLineNumber {
                lines.append(BlameLine(
                    lineNumber: currentLineNumber,
                    revision: currentRevision,
                    author: currentAuthor,
                    date: currentDate
                ))
            }
            currentLineNumber = nil
        default:
            break
        }

        currentText = ""
    }
}
