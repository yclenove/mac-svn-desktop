import Foundation

enum MacSvnCoreModeWidthClass: Equatable {
    case compact
    case regular

    static func resolve(width: CGFloat) -> Self {
        width < 1_180 ? .compact : .regular
    }
}

enum MacSvnCoreModeMetrics {
    static let toolbarHeight: CGFloat = 48
    static let masterMinimumWidth: CGFloat = 320
    static let masterIdealWidth: CGFloat = 360
    static let masterMaximumWidth: CGFloat = 400
    static let inspectorMinimumWidth: CGFloat = 360
}

enum MacSvnLogFilterSummary {
    static func activeCount(
        author: String,
        message: String,
        path: String,
        stopOnCopy: Bool,
        offline: Bool
    ) -> Int {
        [author, message, path]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count + (stopOnCopy ? 1 : 0) + (offline ? 1 : 0)
    }
}

enum MacSvnCoreModeErrorPresentation {
    static func message(_ rawMessage: String) -> String {
        let normalized = rawMessage
            .replacingOccurrences(of: #"\n"#, with: "\n")
            .replacingOccurrences(of: #"\""#, with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercase = normalized.lowercased()

        if lowercase.contains("e215004")
            || lowercase.contains("e170001")
            || lowercase.contains("authentication failed") {
            return "仓库认证失败。请检查凭据或证书信任设置后重试。"
        }
        if lowercase.contains("ssl certificate verification failed") {
            return "SSL 证书校验失败。请检查服务器地址和证书信任设置后重试。"
        }
        if lowercase.contains("timed out") || lowercase.contains("timeout") {
            return "连接仓库超时。请检查网络后重试。"
        }
        if lowercase.contains("e170013")
            || lowercase.contains("e175002")
            || lowercase.contains("unable to connect") {
            return "无法连接到仓库。请检查网络连接和仓库 URL 后重试。"
        }

        let prefix = #"network(detail: ""#
        if normalized.hasPrefix(prefix), normalized.hasSuffix(#"")"#) {
            return String(normalized.dropFirst(prefix.count).dropLast(2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return normalized
    }
}
