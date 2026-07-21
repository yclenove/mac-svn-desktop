import Foundation
import Observation

public protocol BlameDifferenceProviding: Sendable {
    func blame(
        wc: URL,
        target: String,
        startRevision: Revision?,
        endRevision: Revision?
    ) async throws -> [BlameLine]
    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String
}

public enum BlameDifferenceRowKind: Equatable, Sendable {
    case hunk
    case unchanged
    case attributionChanged
    case contentModified
    case added
    case deleted
}

public struct BlameDifferenceCell: Equatable, Sendable {
    public let lineNumber: Int?
    public let text: String
    public let revision: Revision?
    public let author: String?
    public let date: Date?

    public init(
        lineNumber: Int?,
        text: String,
        revision: Revision?,
        author: String?,
        date: Date?
    ) {
        self.lineNumber = lineNumber
        self.text = text
        self.revision = revision
        self.author = author
        self.date = date
    }
}

public struct BlameDifferenceRow: Equatable, Identifiable, Sendable {
    public let id: Int
    public let kind: BlameDifferenceRowKind
    public let left: BlameDifferenceCell?
    public let right: BlameDifferenceCell?

    public init(
        id: Int,
        kind: BlameDifferenceRowKind,
        left: BlameDifferenceCell?,
        right: BlameDifferenceCell?
    ) {
        self.id = id
        self.kind = kind
        self.left = left
        self.right = right
    }
}

public struct BlameDifferenceSummary: Equatable, Sendable {
    public var unchanged = 0
    public var attributionChanged = 0
    public var contentModified = 0
    public var added = 0
    public var deleted = 0

    public init() {}
}

public enum BlameDifferenceBuilder {
    public static func build(
        diffText: String,
        oldBlame: [BlameLine],
        newBlame: [BlameLine]
    ) -> [BlameDifferenceRow] {
        guard DiffPerformanceLimits.shouldParseLineStructures(diffCharacterCount: diffText.count) else {
            return []
        }
        let oldByLine = Dictionary(uniqueKeysWithValues: oldBlame.map { ($0.lineNumber, $0) })
        let newByLine = Dictionary(uniqueKeysWithValues: newBlame.map { ($0.lineNumber, $0) })

        return DiffViewModel.parseSideBySideRows(diffText).enumerated().map { index, row in
            let left = cell(from: row.left, blame: oldByLine)
            let right = cell(from: row.right, blame: newByLine)
            return BlameDifferenceRow(
                id: index,
                kind: kind(for: row.kind, left: left, right: right),
                left: left,
                right: right
            )
        }
    }

    private static func cell(
        from cell: SideBySideDiffCell?,
        blame: [Int: BlameLine]
    ) -> BlameDifferenceCell? {
        guard let cell else { return nil }
        let annotation = cell.lineNumber.flatMap { blame[$0] }
        return BlameDifferenceCell(
            lineNumber: cell.lineNumber,
            text: cell.text,
            revision: annotation?.revision,
            author: annotation?.author,
            date: annotation?.date
        )
    }

    private static func kind(
        for kind: SideBySideDiffRowKind,
        left: BlameDifferenceCell?,
        right: BlameDifferenceCell?
    ) -> BlameDifferenceRowKind {
        switch kind {
        case .hunk:
            return .hunk
        case .deletion:
            return .deleted
        case .addition:
            return .added
        case .modification:
            return .contentModified
        case .context:
            let sameAttribution = left?.revision == right?.revision
                && left?.author == right?.author
                && left?.date == right?.date
            return sameAttribution ? .unchanged : .attributionChanged
        }
    }
}

public enum BlameDifferenceViewState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

@MainActor
@Observable
public final class BlameDifferenceViewModel {
    private let workingCopy: URL
    private let target: String
    private let provider: any BlameDifferenceProviding

    public private(set) var state: BlameDifferenceViewState = .idle
    public private(set) var rows: [BlameDifferenceRow] = []
    public private(set) var summary = BlameDifferenceSummary()
    public private(set) var diffText = ""
    public private(set) var fromRevision: Revision?
    public private(set) var toRevision: Revision?

    public init(
        workingCopy: URL,
        target: String,
        provider: any BlameDifferenceProviding
    ) {
        self.workingCopy = workingCopy
        self.target = target
        self.provider = provider
    }

    public var changedRows: [BlameDifferenceRow] {
        rows.filter { $0.kind != .hunk && $0.kind != .unchanged }
    }

    public func load(from: Revision, to: Revision) async {
        guard from.value > 0, to.value > 0 else {
            state = .error("修订号必须是正整数")
            return
        }
        guard from.value < to.value else {
            state = .error("旧修订必须小于新修订")
            return
        }

        state = .loading
        rows = []
        summary = BlameDifferenceSummary()
        diffText = ""
        fromRevision = from
        toRevision = to

        do {
            let oldBlame = try await provider.blame(
                wc: workingCopy,
                target: target,
                startRevision: nil,
                endRevision: from
            )
            let newBlame = try await provider.blame(
                wc: workingCopy,
                target: target,
                startRevision: nil,
                endRevision: to
            )
            diffText = try await provider.diff(
                wc: workingCopy,
                target: target,
                r1: from,
                r2: to
            )
            rows = BlameDifferenceBuilder.build(
                diffText: diffText,
                oldBlame: oldBlame,
                newBlame: newBlame
            )
            summary = Self.summarize(rows)
            state = .loaded
        } catch {
            rows = []
            summary = BlameDifferenceSummary()
            state = .error(String(describing: error))
        }
    }

    private static func summarize(_ rows: [BlameDifferenceRow]) -> BlameDifferenceSummary {
        var summary = BlameDifferenceSummary()
        for row in rows {
            switch row.kind {
            case .hunk: break
            case .unchanged: summary.unchanged += 1
            case .attributionChanged: summary.attributionChanged += 1
            case .contentModified: summary.contentModified += 1
            case .added: summary.added += 1
            case .deleted: summary.deleted += 1
            }
        }
        return summary
    }
}

extension SvnService: BlameDifferenceProviding {}
