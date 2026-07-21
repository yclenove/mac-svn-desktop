import Foundation
import Observation

public protocol DiffProviding: Sendable {
    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String
    func diffWithURL(
        wc: URL,
        target: String,
        url: String,
        revision: Revision?,
        auth: Credential?
    ) async throws -> String
    func diffBetweenPaths(wc: URL, oldPath: String, newPath: String) async throws -> String
    func diffAgainstBase(wc: URL, target: String) async throws -> String
}

extension DiffProviding {
    public func diffWithURL(
        wc: URL,
        target: String,
        url: String,
        revision: Revision?,
        auth: Credential?
    ) async throws -> String {
        throw SvnError.other(code: nil, stderr: "diffWithURLUnavailable")
    }

    /// 默认回退不支持双路径；生产路径由 `SvnService` 覆盖。
    public func diffBetweenPaths(wc: URL, oldPath: String, newPath: String) async throws -> String {
        throw SvnError.other(code: nil, stderr: "diffBetweenPathsUnavailable")
    }

    public func diffAgainstBase(wc: URL, target: String) async throws -> String {
        try await diff(wc: wc, target: target, r1: nil, r2: nil)
    }
}

public struct BinaryFileDetails: Equatable, Sendable {
    public let size: UInt64?
    public let modifiedAt: Date?

    public init(size: UInt64?, modifiedAt: Date?) {
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

public enum DiffViewState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case binaryUnsupported(BinaryFileDetails?)
    case error(String)
}

public enum ExternalDiffState: Equatable, Sendable {
    case idle
    case opening
    case opened(ExternalDiffLaunchResult)
    case error(String)
}

public enum UnifiedDiffLineKind: Equatable, Sendable {
    case metadata
    case hunk
    case addition
    case deletion
    case context
    case noNewlineMarker
}

public struct UnifiedDiffLine: Equatable, Identifiable, Sendable {
    public let id: Int
    public let text: String
    public let kind: UnifiedDiffLineKind

    public init(id: Int, text: String, kind: UnifiedDiffLineKind) {
        self.id = id
        self.text = text
        self.kind = kind
    }
}

public enum SideBySideDiffRowKind: Equatable, Sendable {
    case hunk
    case context
    case deletion
    case addition
    case modification
}

public enum SideBySideDiffCellKind: Equatable, Sendable {
    case context
    case deletion
    case addition
    case modified
}

public enum InlineDiffSpanKind: Equatable, Sendable {
    case changed
}

public struct InlineDiffSpan: Equatable, Sendable {
    public let start: Int
    public let length: Int
    public let kind: InlineDiffSpanKind

    public init(start: Int, length: Int, kind: InlineDiffSpanKind) {
        self.start = start
        self.length = length
        self.kind = kind
    }
}

public struct SideBySideDiffCell: Equatable, Sendable {
    public let lineNumber: Int?
    public let text: String
    public let kind: SideBySideDiffCellKind
    public let inlineSpans: [InlineDiffSpan]

    public init(
        lineNumber: Int?,
        text: String,
        kind: SideBySideDiffCellKind,
        inlineSpans: [InlineDiffSpan] = []
    ) {
        self.lineNumber = lineNumber
        self.text = text
        self.kind = kind
        self.inlineSpans = inlineSpans
    }
}

public struct SideBySideDiffRow: Equatable, Identifiable, Sendable {
    public let id: Int
    public let kind: SideBySideDiffRowKind
    public let left: SideBySideDiffCell?
    public let right: SideBySideDiffCell?

    public init(
        id: Int,
        kind: SideBySideDiffRowKind,
        left: SideBySideDiffCell?,
        right: SideBySideDiffCell?
    ) {
        self.id = id
        self.kind = kind
        self.left = left
        self.right = right
    }
}

public struct SideBySideDiffColumns: Equatable, Sendable {
    public let left: String
    public let right: String

    public init(left: String, right: String) {
        self.left = left
        self.right = right
    }
}

@MainActor
@Observable
public final class DiffViewModel {
    private let workingCopy: URL
    private let diffProvider: any DiffProviding
    private let externalDiffOpener: (any ExternalDiffOpening)?
    private var requestGeneration = 0

    public private(set) var state: DiffViewState = .idle
    public private(set) var externalDiffState: ExternalDiffState = .idle
    public private(set) var diffText = ""
    public private(set) var lines: [UnifiedDiffLine] = []
    public private(set) var sideBySideRows: [SideBySideDiffRow] = []

    public init(
        workingCopy: URL,
        diffProvider: any DiffProviding,
        externalDiffOpener: (any ExternalDiffOpening)? = nil
    ) {
        self.workingCopy = workingCopy
        self.diffProvider = diffProvider
        self.externalDiffOpener = externalDiffOpener
    }

    public func load(target: String, r1: Revision? = nil, r2: Revision? = nil) async {
        let generation = beginLoad()

        do {
            let rawDiff = try await diffProvider.diff(wc: workingCopy, target: target, r1: r1, r2: r2)
            guard generation == requestGeneration else { return }
            applyLoadedDiff(rawDiff, target: target)
        } catch {
            guard generation == requestGeneration else { return }
            failLoad(error)
        }
    }

    /// 工作副本目标与任意仓库 URL（可带 peg revision）的 Diff。
    public func loadWithURL(
        target: String,
        url: String,
        revisionText: String = "",
        auth: Credential? = nil
    ) async {
        let generation = beginLoad()

        do {
            let request = try DiffWithURLValidationPolicy.validate(
                workingCopy: workingCopy,
                target: target,
                url: url,
                revisionText: revisionText
            )
            let rawDiff = try await diffProvider.diffWithURL(
                wc: request.workingCopy,
                target: request.target,
                url: request.url,
                revision: request.revision,
                auth: auth
            )
            guard generation == requestGeneration else { return }
            applyLoadedDiff(rawDiff, target: request.target)
        } catch {
            guard generation == requestGeneration else { return }
            failLoad(error)
        }
    }

    /// 显式对比 BASE（`svn diff -r BASE`）
    public func loadAgainstBase(target: String) async {
        let generation = beginLoad()

        do {
            let rawDiff = try await diffProvider.diffAgainstBase(wc: workingCopy, target: target)
            guard generation == requestGeneration else { return }
            applyLoadedDiff(rawDiff, target: target)
        } catch {
            guard generation == requestGeneration else { return }
            failLoad(error)
        }
    }

    /// 双任意文件 Diff（`svn diff --old --new`）
    public func loadBetweenPaths(oldPath: String, newPath: String) async {
        let generation = beginLoad()

        do {
            let rawDiff = try await diffProvider.diffBetweenPaths(
                wc: workingCopy,
                oldPath: oldPath,
                newPath: newPath
            )
            guard generation == requestGeneration else { return }
            applyLoadedDiff(rawDiff, target: newPath)
        } catch {
            guard generation == requestGeneration else { return }
            failLoad(error)
        }
    }

    /// 清空展示但不销毁实例（嵌入工作区切换选中时用）。
    public func clearDisplay() {
        requestGeneration += 1
        diffText = ""
        lines = []
        sideBySideRows = []
        state = .idle
        externalDiffState = .idle
    }

    private func beginLoad() -> Int {
        requestGeneration += 1
        state = .loading
        return requestGeneration
    }

    public func openExternalDiff(
        target: String,
        tool: ExternalDiffToolConfiguration,
        r1: Revision? = nil,
        r2: Revision? = nil
    ) async {
        guard let externalDiffOpener else {
            externalDiffState = .error("externalDiffUnavailable")
            return
        }

        externalDiffState = .opening

        do {
            let result = try await externalDiffOpener.open(
                wc: workingCopy,
                target: target,
                tool: tool,
                r1: r1,
                r2: r2
            )
            externalDiffState = .opened(result)
        } catch {
            externalDiffState = .error(String(describing: error))
        }
    }

    private func applyLoadedDiff(_ rawDiff: String, target: String) {
        diffText = rawDiff

        if Self.isBinaryUnsupportedDiff(rawDiff) {
            lines = []
            sideBySideRows = []
            state = .binaryUnsupported(binaryDetails(for: target))
            return
        }

        if DiffPerformanceLimits.shouldParseLineStructures(diffCharacterCount: rawDiff.count) {
            lines = Self.parseLines(rawDiff)
            sideBySideRows = Self.parseSideBySideRows(rawDiff)
        } else {
            lines = []
            sideBySideRows = []
        }
        state = .loaded
    }

    private func failLoad(_ error: Error) {
        diffText = ""
        lines = []
        sideBySideRows = []
        state = .error(String(describing: error))
    }

    nonisolated public static func parseLines(_ diff: String) -> [UnifiedDiffLine] {
        diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { index, line in
            let text = String(line)
            return UnifiedDiffLine(id: index, text: text, kind: classify(text))
        }
    }

    /// 嵌入工作区的左右分栏使用两块完整 Text，避免为每一行创建 SwiftUI 节点。
    nonisolated public static func sideBySideColumnTexts(_ rows: [SideBySideDiffRow]) -> SideBySideDiffColumns {
        func displayText(_ cell: SideBySideDiffCell?) -> String {
            guard let cell else { return "" }
            let number = cell.lineNumber.map(String.init) ?? ""
            return number.isEmpty ? cell.text : "\(number)  \(cell.text)"
        }

        return SideBySideDiffColumns(
            left: rows.map { displayText($0.left) }.joined(separator: "\n"),
            right: rows.map { displayText($0.right) }.joined(separator: "\n")
        )
    }

    nonisolated public static func parseSideBySideRows(_ diff: String) -> [SideBySideDiffRow] {
        struct PendingLine {
            let number: Int
            let text: String
        }

        var rows: [SideBySideDiffRow] = []
        var oldLineNumber = 0
        var newLineNumber = 0
        var inHunk = false
        var pendingDeletions: [PendingLine] = []
        var pendingAdditions: [PendingLine] = []

        func appendRow(
            kind: SideBySideDiffRowKind,
            left: SideBySideDiffCell?,
            right: SideBySideDiffCell?
        ) {
            rows.append(SideBySideDiffRow(
                id: rows.count,
                kind: kind,
                left: left,
                right: right
            ))
        }

        func flushPendingChanges() {
            let pairedCount = min(pendingDeletions.count, pendingAdditions.count)

            for index in 0..<pairedCount {
                let deletion = pendingDeletions[index]
                let addition = pendingAdditions[index]
                let spans = inlineChangedSpans(left: deletion.text, right: addition.text)

                appendRow(
                    kind: .modification,
                    left: SideBySideDiffCell(
                        lineNumber: deletion.number,
                        text: deletion.text,
                        kind: .modified,
                        inlineSpans: spans.left
                    ),
                    right: SideBySideDiffCell(
                        lineNumber: addition.number,
                        text: addition.text,
                        kind: .modified,
                        inlineSpans: spans.right
                    )
                )
            }

            if pendingDeletions.count > pairedCount {
                for deletion in pendingDeletions[pairedCount...] {
                    appendRow(
                        kind: .deletion,
                        left: SideBySideDiffCell(
                            lineNumber: deletion.number,
                            text: deletion.text,
                            kind: .deletion
                        ),
                        right: nil
                    )
                }
            }

            if pendingAdditions.count > pairedCount {
                for addition in pendingAdditions[pairedCount...] {
                    appendRow(
                        kind: .addition,
                        left: nil,
                        right: SideBySideDiffCell(
                            lineNumber: addition.number,
                            text: addition.text,
                            kind: .addition
                        )
                    )
                }
            }

            pendingDeletions = []
            pendingAdditions = []
        }

        for rawLine in diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if rawLine.hasPrefix("@@") {
                flushPendingChanges()
                if let lineNumbers = hunkLineNumbers(from: rawLine) {
                    oldLineNumber = lineNumbers.old
                    newLineNumber = lineNumbers.new
                }
                inHunk = true
                appendRow(
                    kind: .hunk,
                    left: SideBySideDiffCell(lineNumber: nil, text: rawLine, kind: .context),
                    right: SideBySideDiffCell(lineNumber: nil, text: rawLine, kind: .context)
                )
                continue
            }

            guard inHunk else {
                continue
            }

            if rawLine.hasPrefix("\\") {
                continue
            }

            if rawLine.hasPrefix("-") {
                pendingDeletions.append(PendingLine(
                    number: oldLineNumber,
                    text: String(rawLine.dropFirst())
                ))
                oldLineNumber += 1
                continue
            }

            if rawLine.hasPrefix("+") {
                pendingAdditions.append(PendingLine(
                    number: newLineNumber,
                    text: String(rawLine.dropFirst())
                ))
                newLineNumber += 1
                continue
            }

            if rawLine.hasPrefix(" ") {
                flushPendingChanges()
                let text = String(rawLine.dropFirst())
                appendRow(
                    kind: .context,
                    left: SideBySideDiffCell(lineNumber: oldLineNumber, text: text, kind: .context),
                    right: SideBySideDiffCell(lineNumber: newLineNumber, text: text, kind: .context)
                )
                oldLineNumber += 1
                newLineNumber += 1
            }
        }

        flushPendingChanges()
        return rows
    }

    nonisolated private static func classify(_ line: String) -> UnifiedDiffLineKind {
        if line.hasPrefix("@@") {
            return .hunk
        }

        if line.hasPrefix("+++")
            || line.hasPrefix("---")
            || line.hasPrefix("Index:")
            || line.hasPrefix("===") {
            return .metadata
        }

        if line.hasPrefix("+") {
            return .addition
        }

        if line.hasPrefix("-") {
            return .deletion
        }

        if line.hasPrefix("\\") {
            return .noNewlineMarker
        }

        return .context
    }

    nonisolated private static func isBinaryUnsupportedDiff(_ diff: String) -> Bool {
        let normalized = diff.lowercased()
        return (normalized.contains("cannot display") && normalized.contains("binary"))
            || normalized.contains("binary files")
    }

    nonisolated private static func hunkLineNumbers(from line: String) -> (old: Int, new: Int)? {
        let pattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = expression.firstMatch(in: line, range: range),
              match.numberOfRanges == 3,
              let oldRange = Range(match.range(at: 1), in: line),
              let newRange = Range(match.range(at: 2), in: line),
              let oldStart = Int(line[oldRange]),
              let newStart = Int(line[newRange]) else {
            return nil
        }

        return (oldStart, newStart)
    }

    nonisolated private static func inlineChangedSpans(
        left: String,
        right: String
    ) -> (left: [InlineDiffSpan], right: [InlineDiffSpan]) {
        let leftCharacters = Array(left)
        let rightCharacters = Array(right)
        let table = lcsTable(leftCharacters, rightCharacters)
        var leftSpans: [InlineDiffSpan] = []
        var rightSpans: [InlineDiffSpan] = []
        var leftChangedStart: Int?
        var rightChangedStart: Int?
        var leftChangedLength = 0
        var rightChangedLength = 0
        var leftIndex = 0
        var rightIndex = 0

        func flushChangedSpans() {
            if let leftChangedStart, leftChangedLength > 0 {
                leftSpans.append(InlineDiffSpan(
                    start: leftChangedStart,
                    length: leftChangedLength,
                    kind: .changed
                ))
            }

            if let rightChangedStart, rightChangedLength > 0 {
                rightSpans.append(InlineDiffSpan(
                    start: rightChangedStart,
                    length: rightChangedLength,
                    kind: .changed
                ))
            }

            leftChangedStart = nil
            rightChangedStart = nil
            leftChangedLength = 0
            rightChangedLength = 0
        }

        func markLeftChanged() {
            if leftChangedStart == nil {
                leftChangedStart = leftIndex
            }
            leftChangedLength += 1
            leftIndex += 1
        }

        func markRightChanged() {
            if rightChangedStart == nil {
                rightChangedStart = rightIndex
            }
            rightChangedLength += 1
            rightIndex += 1
        }

        while leftIndex < leftCharacters.count || rightIndex < rightCharacters.count {
            if leftIndex < leftCharacters.count,
               rightIndex < rightCharacters.count,
               leftCharacters[leftIndex] == rightCharacters[rightIndex] {
                flushChangedSpans()
                leftIndex += 1
                rightIndex += 1
            } else if rightIndex < rightCharacters.count,
                      (leftIndex == leftCharacters.count
                        || table[leftIndex][rightIndex + 1] > table[leftIndex + 1][rightIndex]) {
                markRightChanged()
            } else if leftIndex < leftCharacters.count {
                markLeftChanged()
            }
        }

        flushChangedSpans()
        return (leftSpans, rightSpans)
    }

    nonisolated private static func lcsTable<T: Equatable>(_ left: [T], _ right: [T]) -> [[Int]] {
        var table = Array(
            repeating: Array(repeating: 0, count: right.count + 1),
            count: left.count + 1
        )

        guard !left.isEmpty, !right.isEmpty else {
            return table
        }

        for leftIndex in stride(from: left.count - 1, through: 0, by: -1) {
            for rightIndex in stride(from: right.count - 1, through: 0, by: -1) {
                if left[leftIndex] == right[rightIndex] {
                    table[leftIndex][rightIndex] = table[leftIndex + 1][rightIndex + 1] + 1
                } else {
                    table[leftIndex][rightIndex] = max(
                        table[leftIndex + 1][rightIndex],
                        table[leftIndex][rightIndex + 1]
                    )
                }
            }
        }

        return table
    }

    private func binaryDetails(for target: String) -> BinaryFileDetails? {
        let fileURL = workingCopy.appendingPathComponent(target)

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else {
            return nil
        }

        let size = (attributes[.size] as? NSNumber)?.uint64Value
        let modifiedAt = attributes[.modificationDate] as? Date
        return BinaryFileDetails(size: size, modifiedAt: modifiedAt)
    }
}

extension SvnService: DiffProviding {}
