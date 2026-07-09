import Foundation

public struct MacSvnDeepLinkParser: Sendable {
    public init() {}

    public func parse(_ url: URL) throws -> MacSvnDeepLinkAction {
        guard url.scheme?.lowercased() == "macsvn" else {
            throw MacSvnDeepLinkParserError.invalidScheme(url.scheme)
        }
        guard let route = url.host?.lowercased(), !route.isEmpty else {
            throw MacSvnDeepLinkParserError.missingRoute
        }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var values: [String: String] = [:]
        for item in items {
            if let value = item.value {
                values[item.name.lowercased()] = value
            }
        }

        switch route {
        case "open":
            guard let path = values["path"], !path.isEmpty else {
                throw MacSvnDeepLinkParserError.missingParameter("path")
            }
            return .open(path: path)
        case "log":
            let target = try target(from: values)
            return .log(target: target, revision: try optionalRevision(values["rev"]))
        case "diff":
            let target = try target(from: values)
            let from = try optionalRevision(values["from"])
            let to = try optionalRevision(values["to"])
            let range = try revisionRange(from: from, to: to)
            return .diff(target: target, range: range)
        default:
            throw MacSvnDeepLinkParserError.unknownRoute(route)
        }
    }

    private func target(from values: [String: String]) throws -> MacSvnAutomationTarget {
        if let path = values["path"], !path.isEmpty {
            return .path(path)
        }
        if let url = values["url"], !url.isEmpty {
            return .repositoryURL(url)
        }
        throw MacSvnDeepLinkParserError.missingTarget
    }

    private func optionalRevision(_ value: String?) throws -> Revision? {
        guard let value, !value.isEmpty else {
            return nil
        }
        let normalized = value.lowercased().hasPrefix("r") ? String(value.dropFirst()) : value
        guard let intValue = Int(normalized) else {
            throw MacSvnDeepLinkParserError.invalidRevision(value)
        }
        return Revision(intValue)
    }

    private func revisionRange(from: Revision?, to: Revision?) throws -> RevisionRange? {
        switch (from, to) {
        case let (.some(start), .some(end)):
            return RevisionRange(start: start, end: end)
        case (nil, nil):
            return nil
        case (.some, nil):
            throw MacSvnDeepLinkParserError.missingParameter("to")
        case (nil, .some):
            throw MacSvnDeepLinkParserError.missingParameter("from")
        }
    }
}
