import Foundation

public struct ChangelistGroup: Identifiable, Equatable, Sendable {
    public let name: String?
    public let entries: [FileStatus]

    public var id: String { name ?? "__unassigned__" }
    public var displayName: String { name ?? "未分配" }

    public init(name: String?, entries: [FileStatus]) {
        self.name = name
        self.entries = entries
    }
}

public enum ChangelistValidationError: Error, Equatable, LocalizedError {
    case emptyName
    case noPaths

    public var errorDescription: String? {
        switch self {
        case .emptyName: "变更列表名称不能为空"
        case .noPaths: "请至少选择一个版本化路径"
        }
    }
}

public enum ChangelistPolicy: Sendable {
    public static let ignoreOnCommitName = "ignore-on-commit"

    public static func validatedName(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ChangelistValidationError.emptyName }
        return trimmed
    }

    public static func validatedPaths(_ paths: [String]) throws -> [String] {
        let normalized = Array(Set(paths.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()
        guard !normalized.isEmpty else { throw ChangelistValidationError.noPaths }
        return normalized
    }

    public static func isIgnoredOnCommit(_ name: String?) -> Bool {
        name?.caseInsensitiveCompare(ignoreOnCommitName) == .orderedSame
    }

    public static func groups(from statuses: [FileStatus]) -> [ChangelistGroup] {
        let grouped = Dictionary(grouping: statuses, by: \.changelist)
        let named = grouped.keys.compactMap { $0 }.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        var result = named.map { name in
            ChangelistGroup(
                name: name,
                entries: grouped[name, default: []].sorted { $0.path < $1.path }
            )
        }
        if let unassigned = grouped[nil], !unassigned.isEmpty {
            result.append(ChangelistGroup(
                name: nil,
                entries: unassigned.sorted { $0.path < $1.path }
            ))
        }
        return result
    }
}
