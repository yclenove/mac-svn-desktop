import Foundation

public enum DiffEdit: Equatable, Sendable {
    case equal(String)
    case delete(String)
    case insert(String)
}

public enum MergeBlock: Equatable, Sendable {
    case stable(lines: [String])
    case conflict(ConflictHunk)
}

public struct ConflictHunk: Equatable, Sendable {
    public let baseLines: [String]
    public let mineLines: [String]
    public let theirsLines: [String]
    public var resolution: Resolution?

    public init(
        baseLines: [String],
        mineLines: [String],
        theirsLines: [String],
        resolution: Resolution? = nil
    ) {
        self.baseLines = baseLines
        self.mineLines = mineLines
        self.theirsLines = theirsLines
        self.resolution = resolution
    }

    public enum Resolution: Equatable, Sendable {
        case takeMine
        case takeTheirs
        case takeBoth(mineFirst: Bool)
        case manual(lines: [String])
    }

    public func resolvedLines() -> [String]? {
        guard let resolution else {
            return nil
        }

        switch resolution {
        case .takeMine:
            return mineLines
        case .takeTheirs:
            return theirsLines
        case .takeBoth(let mineFirst):
            return mineFirst ? mineLines + theirsLines : theirsLines + mineLines
        case .manual(let lines):
            return lines
        }
    }
}

public enum MergeEngine {
    public static func diff(_ a: [Substring], _ b: [Substring]) -> [DiffEdit] {
        let source = a.map(String.init)
        let target = b.map(String.init)
        let table = lcsTable(source, target)

        var edits: [DiffEdit] = []
        var i = 0
        var j = 0

        while i < source.count || j < target.count {
            if i < source.count, j < target.count, source[i] == target[j] {
                edits.append(.equal(source[i]))
                i += 1
                j += 1
            } else if j < target.count, (i == source.count || table[i][j + 1] > table[i + 1][j]) {
                edits.append(.insert(target[j]))
                j += 1
            } else if i < source.count {
                edits.append(.delete(source[i]))
                i += 1
            }
        }

        return edits
    }

    public static func merge3(base: [Substring], mine: [Substring], theirs: [Substring]) -> [MergeBlock] {
        let baseLines = base.map(String.init)
        let mineChanges = changes(from: baseLines, to: mine.map(String.init))
        let theirsChanges = changes(from: baseLines, to: theirs.map(String.init))
        var mineIndex = 0
        var theirsIndex = 0
        var baseCursor = 0
        var blocks: [MergeBlock] = []

        while mineIndex < mineChanges.count || theirsIndex < theirsChanges.count {
            let nextMineStart = mineIndex < mineChanges.count ? mineChanges[mineIndex].start : Int.max
            let nextTheirsStart = theirsIndex < theirsChanges.count ? theirsChanges[theirsIndex].start : Int.max
            var candidateStart = min(nextMineStart, nextTheirsStart)
            var candidateEnd = candidateStart
            var candidateMineChanges: [Change] = []
            var candidateTheirsChanges: [Change] = []

            appendStable(Array(baseLines[baseCursor..<candidateStart]), to: &blocks)

            var didExpand = true
            while didExpand {
                didExpand = false

                while mineIndex < mineChanges.count, mineChanges[mineIndex].start <= candidateEnd {
                    let change = mineChanges[mineIndex]
                    candidateStart = min(candidateStart, change.start)
                    candidateEnd = max(candidateEnd, change.end)
                    candidateMineChanges.append(change)
                    mineIndex += 1
                    didExpand = true
                }

                while theirsIndex < theirsChanges.count, theirsChanges[theirsIndex].start <= candidateEnd {
                    let change = theirsChanges[theirsIndex]
                    candidateStart = min(candidateStart, change.start)
                    candidateEnd = max(candidateEnd, change.end)
                    candidateTheirsChanges.append(change)
                    theirsIndex += 1
                    didExpand = true
                }
            }

            let baseSegment = Array(baseLines[candidateStart..<candidateEnd])
            let mineSegment = appliedSegment(
                baseLines: baseLines,
                start: candidateStart,
                end: candidateEnd,
                changes: candidateMineChanges
            )
            let theirsSegment = appliedSegment(
                baseLines: baseLines,
                start: candidateStart,
                end: candidateEnd,
                changes: candidateTheirsChanges
            )

            if mineSegment == theirsSegment {
                appendStable(mineSegment, to: &blocks)
            } else if candidateMineChanges.isEmpty {
                appendStable(theirsSegment, to: &blocks)
            } else if candidateTheirsChanges.isEmpty {
                appendStable(mineSegment, to: &blocks)
            } else {
                blocks.append(.conflict(ConflictHunk(
                    baseLines: baseSegment,
                    mineLines: mineSegment,
                    theirsLines: theirsSegment
                )))
            }

            baseCursor = candidateEnd
        }

        appendStable(Array(baseLines[baseCursor..<baseLines.count]), to: &blocks)
        return blocks
    }

    public static func mergedLines(from blocks: [MergeBlock]) -> [String]? {
        var lines: [String] = []

        for block in blocks {
            switch block {
            case .stable(let stableLines):
                lines += stableLines
            case .conflict(let hunk):
                guard let resolvedLines = hunk.resolvedLines() else {
                    return nil
                }
                lines += resolvedLines
            }
        }

        return lines
    }

    private static func lcsTable(_ source: [String], _ target: [String]) -> [[Int]] {
        var table = Array(
            repeating: Array(repeating: 0, count: target.count + 1),
            count: source.count + 1
        )

        guard !source.isEmpty, !target.isEmpty else {
            return table
        }

        for i in stride(from: source.count - 1, through: 0, by: -1) {
            for j in stride(from: target.count - 1, through: 0, by: -1) {
                if source[i] == target[j] {
                    table[i][j] = table[i + 1][j + 1] + 1
                } else {
                    table[i][j] = max(table[i + 1][j], table[i][j + 1])
                }
            }
        }

        return table
    }

    private struct Change: Equatable {
        let start: Int
        let end: Int
        let replacement: [String]
    }

    private static func changes(from base: [String], to target: [String]) -> [Change] {
        let edits = diff(base.map { Substring($0) }, target.map { Substring($0) })
        var changes: [Change] = []
        var baseIndex = 0
        var changeStart: Int?
        var deletedCount = 0
        var replacement: [String] = []

        func flushChange() {
            guard let start = changeStart else {
                return
            }

            changes.append(Change(
                start: start,
                end: start + deletedCount,
                replacement: replacement
            ))
            changeStart = nil
            deletedCount = 0
            replacement = []
        }

        for edit in edits {
            switch edit {
            case .equal:
                flushChange()
                baseIndex += 1
            case .delete(let line):
                if changeStart == nil {
                    changeStart = baseIndex
                }
                _ = line
                deletedCount += 1
                baseIndex += 1
            case .insert(let line):
                if changeStart == nil {
                    changeStart = baseIndex
                }
                replacement.append(line)
            }
        }

        flushChange()
        return changes
    }

    private static func appliedSegment(
        baseLines: [String],
        start: Int,
        end: Int,
        changes: [Change]
    ) -> [String] {
        guard !changes.isEmpty else {
            return Array(baseLines[start..<end])
        }

        var result: [String] = []
        var cursor = start

        for change in changes {
            if cursor < change.start {
                result += baseLines[cursor..<change.start]
            }
            result += change.replacement
            cursor = change.end
        }

        if cursor < end {
            result += baseLines[cursor..<end]
        }

        return result
    }

    private static func appendStable(_ lines: [String], to blocks: inout [MergeBlock]) {
        guard !lines.isEmpty else {
            return
        }

        if case .stable(let existingLines) = blocks.last {
            blocks[blocks.count - 1] = .stable(lines: existingLines + lines)
        } else {
            blocks.append(.stable(lines: lines))
        }
    }
}
