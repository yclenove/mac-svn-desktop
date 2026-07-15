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
