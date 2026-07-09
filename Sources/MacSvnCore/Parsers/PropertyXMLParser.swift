import Foundation

public enum PropertyXMLParser {
    public static func parse(_ data: Data) throws -> [SvnProperty] {
        let delegate = PropertyXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let detail = parser.parserError?.localizedDescription ?? "Unable to parse svn property XML."
            throw SvnError.parse(detail: detail)
        }

        return delegate.properties
    }
}

private final class PropertyXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var properties: [SvnProperty] = []

    private var currentTarget: String?
    private var currentPropertyName: String?
    private var currentPropertyValue = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "target":
            currentTarget = attributeDict["path"]
        case "property":
            currentPropertyName = attributeDict["name"]
            currentPropertyValue = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentPropertyName != nil else {
            return
        }

        currentPropertyValue += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "property":
            if let currentTarget, let currentPropertyName {
                properties.append(SvnProperty(
                    target: currentTarget,
                    name: currentPropertyName,
                    value: currentPropertyValue
                ))
            }
            currentPropertyName = nil
            currentPropertyValue = ""
        case "target":
            currentTarget = nil
        default:
            break
        }
    }
}
