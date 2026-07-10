import Foundation

/// 将 Finder Sync 菜单动作映射为产品深链（FR-EX-05）。
public struct FinderSyncDeepLinkBuilder: Sendable {
    public init() {}

    public func url(for action: FinderSyncMenuActionID, path: String) -> URL? {
        guard !path.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = ProductBranding.urlScheme

        switch action {
        case .diff:
            components.host = "diff"
            components.queryItems = [URLQueryItem(name: "path", value: path)]
        case .log:
            components.host = "log"
            components.queryItems = [URLQueryItem(name: "path", value: path)]
        case .update, .commit, .revert, .add, .delete, .resolve:
            components.host = "open"
            components.queryItems = [
                URLQueryItem(name: "path", value: path),
                URLQueryItem(name: "action", value: action.rawValue),
            ]
        }

        return components.url
    }
}
