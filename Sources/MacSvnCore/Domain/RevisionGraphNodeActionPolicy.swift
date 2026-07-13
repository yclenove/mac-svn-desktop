import Foundation

public enum RevisionGraphNodeAction: String, CaseIterable, Equatable, Sendable {
    case log
    case checkout
    case blame
    case diff
}

public enum RevisionGraphNodeActionIntent: Equatable, Sendable {
    case log(url: String, revision: Revision)
    case checkout(url: String, revision: Revision)
    case blame(url: String, revision: Revision)
    case diff(nodeID: String)
}

public enum RevisionGraphNodeActionPolicy: Sendable {
    public static func intent(
        for action: RevisionGraphNodeAction,
        node: RevisionGraphNode,
        repositoryRoot: String
    ) -> RevisionGraphNodeActionIntent? {
        switch action {
        case .diff:
            return .diff(nodeID: node.id)
        case .log:
            guard let url = repositoryURL(root: repositoryRoot, path: node.path) else { return nil }
            return .log(url: url, revision: node.revision)
        case .checkout:
            guard let url = repositoryURL(root: repositoryRoot, path: node.path) else { return nil }
            return .checkout(url: url, revision: node.revision)
        case .blame:
            guard let filePath = node.changedPaths.first(where: {
                $0.kind?.lowercased() == "file" && $0.action != .deleted
            })?.path,
            let url = repositoryURL(root: repositoryRoot, path: filePath) else {
                return nil
            }
            return .blame(url: url, revision: node.revision)
        }
    }

    public static func repositoryURL(root: String, path: String) -> String? {
        guard var url = URL(string: root.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil else { return nil }
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            url.appendPathComponent(String(component))
        }
        return url.absoluteString
    }
}
