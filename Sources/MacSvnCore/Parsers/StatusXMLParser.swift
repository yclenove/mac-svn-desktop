import Foundation

public enum StatusXMLParser {
    public static func parse(_ data: Data) throws -> [FileStatus] {
        let delegate = StatusXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let detail = parser.parserError?.localizedDescription ?? "Unable to parse svn status XML."
            throw SvnError.parse(detail: detail)
        }

        return delegate.statuses
    }
}

private final class StatusXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var statuses: [FileStatus] = []

    private var currentPath: String?
    private var currentItemStatus: ItemStatus?
    private var currentRevision: Revision?
    private var currentTreeConflict = false
    private var currentRemoteItemStatus: ItemStatus?
    private var currentChangelist: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "changelist":
            currentChangelist = attributeDict["name"]
        case "entry":
            currentPath = attributeDict["path"]
            currentItemStatus = nil
            currentRevision = nil
            currentTreeConflict = false
            currentRemoteItemStatus = nil
        case "wc-status":
            currentItemStatus = itemStatus(from: attributeDict["item"])
            currentRevision = revision(from: attributeDict["revision"])
            currentTreeConflict = attributeDict["tree-conflicted"] == "true"
        case "repos-status":
            // `svn status -u`：远端将变更状态
            currentRemoteItemStatus = itemStatus(from: attributeDict["item"])
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "changelist" {
            currentChangelist = nil
            return
        }
        guard elementName == "entry", let currentPath, let currentItemStatus else {
            return
        }

        statuses.append(FileStatus(
            path: currentPath,
            itemStatus: currentItemStatus,
            revision: currentRevision,
            isTreeConflict: currentTreeConflict,
            remoteItemStatus: currentRemoteItemStatus,
            changelist: currentChangelist
        ))

        self.currentPath = nil
        self.currentItemStatus = nil
        self.currentRevision = nil
        self.currentTreeConflict = false
        self.currentRemoteItemStatus = nil
    }

    private func itemStatus(from rawValue: String?) -> ItemStatus {
        guard let rawValue else {
            return .none
        }

        return ItemStatus(rawValue: rawValue) ?? .none
    }

    private func revision(from rawValue: String?) -> Revision? {
        guard let rawValue, let value = Int(rawValue) else {
            return nil
        }

        return Revision(value)
    }
}
