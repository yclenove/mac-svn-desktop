import Foundation

public struct RevisionGraphPathClassifier: Sendable {
    private let settings: RevisionGraphSettings

    public init(settings: RevisionGraphSettings) {
        self.settings = settings
    }

    public func classify(_ path: String) -> RevisionGraphPathMatch? {
        let pathComponents = Self.components(path)
        guard !pathComponents.isEmpty else { return nil }

        let groups: [(RevisionGraphNodeCategory, [String])] = [
            (.trunk, settings.trunkPatterns),
            (.branch, settings.branchPatterns),
            (.tag, settings.tagPatterns),
        ]
        for (category, patterns) in groups {
            for pattern in patterns {
                guard let rootLength = Self.matchRootLength(
                    pattern: pattern,
                    pathComponents: pathComponents
                ) else { continue }
                let root = "/" + pathComponents.prefix(rootLength).joined(separator: "/")
                return RevisionGraphPathMatch(rootPath: root, category: category)
            }
        }
        return nil
    }

    private static func matchRootLength(pattern: String, pathComponents: [String]) -> Int? {
        var patternComponents = components(pattern)
        guard !patternComponents.isEmpty else { return nil }
        let acceptsDescendants = patternComponents.last == "**"
        if acceptsDescendants {
            patternComponents.removeLast()
        }
        return match(
            pattern: patternComponents,
            patternIndex: 0,
            path: pathComponents,
            pathIndex: 0,
            acceptsDescendants: acceptsDescendants
        )
    }

    private static func match(
        pattern: [String],
        patternIndex: Int,
        path: [String],
        pathIndex: Int,
        acceptsDescendants: Bool
    ) -> Int? {
        if patternIndex == pattern.count {
            return acceptsDescendants || pathIndex == path.count ? pathIndex : nil
        }
        let component = pattern[patternIndex]
        if component == "**" {
            for nextPathIndex in pathIndex...path.count {
                if let result = match(
                    pattern: pattern,
                    patternIndex: patternIndex + 1,
                    path: path,
                    pathIndex: nextPathIndex,
                    acceptsDescendants: acceptsDescendants
                ) {
                    return result
                }
            }
            return nil
        }
        guard pathIndex < path.count,
              componentMatches(pattern: component, value: path[pathIndex]) else {
            return nil
        }
        return match(
            pattern: pattern,
            patternIndex: patternIndex + 1,
            path: path,
            pathIndex: pathIndex + 1,
            acceptsDescendants: acceptsDescendants
        )
    }

    private static func componentMatches(pattern: String, value: String) -> Bool {
        let pattern = Array(pattern)
        let value = Array(value)
        var table = Array(
            repeating: Array(repeating: false, count: value.count + 1),
            count: pattern.count + 1
        )
        table[0][0] = true
        for patternIndex in 1...pattern.count where pattern[patternIndex - 1] == "*" {
            table[patternIndex][0] = table[patternIndex - 1][0]
        }
        guard !pattern.isEmpty else { return value.isEmpty }
        for patternIndex in 1...pattern.count {
            for valueIndex in 1...value.count {
                switch pattern[patternIndex - 1] {
                case "*":
                    table[patternIndex][valueIndex] = table[patternIndex - 1][valueIndex]
                        || table[patternIndex][valueIndex - 1]
                case "?":
                    table[patternIndex][valueIndex] = table[patternIndex - 1][valueIndex - 1]
                default:
                    table[patternIndex][valueIndex] = table[patternIndex - 1][valueIndex - 1]
                        && pattern[patternIndex - 1] == value[valueIndex - 1]
                }
            }
        }
        return table[pattern.count][value.count]
    }

    static func components(_ path: String) -> [String] {
        path.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
    }
}
