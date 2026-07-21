import Foundation

public enum RevisionGraphBuilder: Sendable {
    public static func build(
        entries: [LogEntry],
        settings: RevisionGraphSettings
    ) -> RevisionGraphSnapshot {
        let classifier = RevisionGraphPathClassifier(settings: settings)
        var nodesByID: [String: RevisionGraphNode] = [:]

        for entry in entries.sorted(by: { $0.revision.value < $1.revision.value }) {
            let grouped = Dictionary(grouping: entry.changedPaths) { change in
                classification(for: change.path, classifier: classifier)
            }
            for (match, changedPaths) in grouped {
                let copyChange = changedPaths.first {
                    $0.copyFromPath != nil && $0.copyFromRevision != nil
                }
                let sourceMatch = copyChange?.copyFromPath.map {
                    classification(for: $0, classifier: classifier)
                }
                let normalizedRoot = normalizePath(match.rootPath)
                let node = RevisionGraphNode(
                    path: normalizedRoot,
                    revision: entry.revision,
                    category: match.category,
                    author: entry.author,
                    date: entry.date,
                    message: entry.message,
                    changedPaths: changedPaths.sorted(by: { $0.path < $1.path }),
                    sourcePath: sourceMatch.map { normalizePath($0.rootPath) },
                    sourceRevision: copyChange?.copyFromRevision,
                    sourceCategory: sourceMatch?.category,
                    isDeleted: changedPaths.contains {
                        normalizePath($0.path) == normalizedRoot && $0.action == .deleted
                    }
                )
                nodesByID[node.id] = node
            }
        }

        for node in Array(nodesByID.values) {
            guard let sourcePath = node.sourcePath,
                  let sourceRevision = node.sourceRevision else { continue }
            let sourceID = RevisionGraphNode.makeID(path: sourcePath, revision: sourceRevision)
            guard nodesByID[sourceID] == nil else { continue }
            nodesByID[sourceID] = RevisionGraphNode(
                path: sourcePath,
                revision: sourceRevision,
                category: node.sourceCategory ?? .unclassified,
                author: "",
                date: nil,
                message: "",
                changedPaths: [],
                isSynthetic: true
            )
        }

        let nodes = nodesByID.values.sorted {
            if $0.revision.value != $1.revision.value {
                return $0.revision.value < $1.revision.value
            }
            return $0.path < $1.path
        }
        var edges = Set<RevisionGraphEdge>()
        for pathNodes in Dictionary(grouping: nodes, by: \.path).values {
            let ordered = pathNodes.sorted(by: { $0.revision.value < $1.revision.value })
            for pair in zip(ordered, ordered.dropFirst()) {
                edges.insert(RevisionGraphEdge(
                    sourceID: pair.0.id,
                    targetID: pair.1.id,
                    kind: .history
                ))
            }
        }
        for node in nodes {
            guard let sourcePath = node.sourcePath,
                  let sourceRevision = node.sourceRevision else { continue }
            edges.insert(RevisionGraphEdge(
                sourceID: RevisionGraphNode.makeID(path: sourcePath, revision: sourceRevision),
                targetID: node.id,
                kind: .copy
            ))
        }
        let orderedEdges = edges.sorted {
            if $0.targetID != $1.targetID { return $0.targetID < $1.targetID }
            if $0.sourceID != $1.sourceID { return $0.sourceID < $1.sourceID }
            return $0.kind.rawValue < $1.kind.rawValue
        }
        return RevisionGraphSnapshot(nodes: nodes, edges: orderedEdges)
    }

    private static func classification(
        for path: String,
        classifier: RevisionGraphPathClassifier
    ) -> RevisionGraphPathMatch {
        if let match = classifier.classify(path) {
            return match
        }
        let components = RevisionGraphPathClassifier.components(path)
        let root = components.first.map { "/\($0)" } ?? "/"
        return RevisionGraphPathMatch(rootPath: root, category: .unclassified)
    }

    private static func normalizePath(_ path: String) -> String {
        let components = RevisionGraphPathClassifier.components(path)
        return components.isEmpty ? "/" : "/" + components.joined(separator: "/")
    }
}
