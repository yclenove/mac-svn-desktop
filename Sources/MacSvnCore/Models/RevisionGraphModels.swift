import Foundation

public enum RevisionGraphNodeCategory: String, Codable, CaseIterable, Equatable, Sendable {
    case trunk
    case branch
    case tag
    case unclassified
}

public enum RevisionGraphViewMode: String, Codable, CaseIterable, Equatable, Sendable {
    case topology
    case timeline
}

public struct RevisionGraphPalette: Codable, Equatable, Sendable {
    public var trunkHex: String
    public var branchHex: String
    public var tagHex: String
    public var unclassifiedHex: String

    public init(
        trunkHex: String = "#2E7D32",
        branchHex: String = "#1565C0",
        tagHex: String = "#AD1457",
        unclassifiedHex: String = "#616161"
    ) {
        self.trunkHex = trunkHex
        self.branchHex = branchHex
        self.tagHex = tagHex
        self.unclassifiedHex = unclassifiedHex
    }
}

public struct RevisionGraphSettings: Codable, Equatable, Sendable {
    public var trunkPatterns: [String]
    public var branchPatterns: [String]
    public var tagPatterns: [String]
    public var blendCopyColors: Bool
    public var palette: RevisionGraphPalette

    public init(
        trunkPatterns: [String] = ["trunk/**", "**/trunk/**"],
        branchPatterns: [String] = ["branches/*/**", "**/branches/*/**"],
        tagPatterns: [String] = ["tags/*/**", "**/tags/*/**"],
        blendCopyColors: Bool = true,
        palette: RevisionGraphPalette = RevisionGraphPalette()
    ) {
        self.trunkPatterns = trunkPatterns
        self.branchPatterns = branchPatterns
        self.tagPatterns = tagPatterns
        self.blendCopyColors = blendCopyColors
        self.palette = palette
    }
}

public struct RevisionGraphPathMatch: Equatable, Hashable, Sendable {
    public let rootPath: String
    public let category: RevisionGraphNodeCategory

    public init(rootPath: String, category: RevisionGraphNodeCategory) {
        self.rootPath = rootPath
        self.category = category
    }
}

public struct RevisionGraphNode: Identifiable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let revision: Revision
    public let category: RevisionGraphNodeCategory
    public let author: String
    public let date: Date?
    public let message: String
    public let changedPaths: [ChangedPath]
    public let sourcePath: String?
    public let sourceRevision: Revision?
    public let sourceCategory: RevisionGraphNodeCategory?
    public let isDeleted: Bool
    public let isSynthetic: Bool

    public init(
        path: String,
        revision: Revision,
        category: RevisionGraphNodeCategory,
        author: String,
        date: Date?,
        message: String,
        changedPaths: [ChangedPath],
        sourcePath: String? = nil,
        sourceRevision: Revision? = nil,
        sourceCategory: RevisionGraphNodeCategory? = nil,
        isDeleted: Bool = false,
        isSynthetic: Bool = false
    ) {
        self.id = Self.makeID(path: path, revision: revision)
        self.path = path
        self.revision = revision
        self.category = category
        self.author = author
        self.date = date
        self.message = message
        self.changedPaths = changedPaths
        self.sourcePath = sourcePath
        self.sourceRevision = sourceRevision
        self.sourceCategory = sourceCategory
        self.isDeleted = isDeleted
        self.isSynthetic = isSynthetic
    }

    public static func makeID(path: String, revision: Revision) -> String {
        "\(path)@\(revision.value)"
    }
}

public struct RevisionGraphEdge: Equatable, Hashable, Sendable {
    public enum Kind: String, Equatable, Hashable, Sendable {
        case history
        case copy
    }

    public let sourceID: String
    public let targetID: String
    public let kind: Kind

    public init(sourceID: String, targetID: String, kind: Kind) {
        self.sourceID = sourceID
        self.targetID = targetID
        self.kind = kind
    }
}

public struct RevisionGraphPruning: Equatable, Sendable {
    public var includeTags: Bool
    public var includeUnclassified: Bool
    public var includeDeleted: Bool
    public var minimumRevision: Revision?
    public var query: String

    public init(
        includeTags: Bool = true,
        includeUnclassified: Bool = true,
        includeDeleted: Bool = true,
        minimumRevision: Revision? = nil,
        query: String = ""
    ) {
        self.includeTags = includeTags
        self.includeUnclassified = includeUnclassified
        self.includeDeleted = includeDeleted
        self.minimumRevision = minimumRevision
        self.query = query
    }
}

public struct RevisionGraphSnapshot: Equatable, Sendable {
    public let nodes: [RevisionGraphNode]
    public let edges: [RevisionGraphEdge]

    public init(nodes: [RevisionGraphNode] = [], edges: [RevisionGraphEdge] = []) {
        self.nodes = nodes
        self.edges = edges
    }

    public func pruned(by pruning: RevisionGraphPruning) -> RevisionGraphSnapshot {
        let query = pruning.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let visibleNodes = nodes.filter { node in
            if !pruning.includeTags, node.category == .tag { return false }
            if !pruning.includeUnclassified, node.category == .unclassified { return false }
            if !pruning.includeDeleted, node.isDeleted { return false }
            if let minimumRevision = pruning.minimumRevision,
               node.revision.value < minimumRevision.value {
                return false
            }
            guard !query.isEmpty else { return true }
            return node.path.lowercased().contains(query)
                || node.author.lowercased().contains(query)
                || node.message.lowercased().contains(query)
        }
        let visibleIDs = Set(visibleNodes.map(\.id))
        let visibleEdges = edges.filter {
            visibleIDs.contains($0.sourceID) && visibleIDs.contains($0.targetID)
        }
        return RevisionGraphSnapshot(nodes: visibleNodes, edges: visibleEdges)
    }
}
