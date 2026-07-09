import Foundation
import Observation

public protocol TextConflictLoading: Sendable {
    func loadTextConflict(_ conflict: ConflictInfo) async throws -> (base: String, mine: String, theirs: String)
}

public protocol ConflictResolutionSaving: Sendable {
    func saveResolution(_ conflict: ConflictInfo, wc: URL, mergedText: String) async throws
}

public enum MergeEditorState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case saving
    case saved
    case error(String)
}

@MainActor
@Observable
public final class MergeEditorViewModel {
    private let provider: any TextConflictLoading & ConflictResolutionSaving
    private var preservesTrailingNewline = false

    public private(set) var state: MergeEditorState = .idle
    public private(set) var conflict: ConflictInfo?
    public private(set) var workingCopy: URL?
    public private(set) var blocks: [MergeBlock] = []
    public private(set) var currentConflictIndex = 0

    public init(provider: any TextConflictLoading & ConflictResolutionSaving) {
        self.provider = provider
    }

    public var conflictBlockIndices: [Int] {
        blocks.indices.compactMap { index in
            if case .conflict = blocks[index] {
                return index
            }
            return nil
        }
    }

    public var unresolvedConflictCount: Int {
        blocks.reduce(0) { count, block in
            guard case .conflict(let hunk) = block, hunk.resolution == nil else {
                return count
            }
            return count + 1
        }
    }

    public var canSaveResolved: Bool {
        state == .loaded && unresolvedConflictCount == 0
    }

    public var currentBlockIndex: Int? {
        let indices = conflictBlockIndices
        guard indices.indices.contains(currentConflictIndex) else {
            return nil
        }

        return indices[currentConflictIndex]
    }

    public func load(conflict: ConflictInfo, wc: URL) async {
        state = .loading
        self.conflict = conflict
        workingCopy = wc
        blocks = []
        currentConflictIndex = 0

        do {
            let text = try await provider.loadTextConflict(conflict)
            preservesTrailingNewline = text.mine.hasSuffix("\n")
            blocks = MergeEngine.merge3(
                base: Self.lines(text.base),
                mine: Self.lines(text.mine),
                theirs: Self.lines(text.theirs)
            )
            currentConflictIndex = conflictBlockIndices.isEmpty ? 0 : 0
            state = .loaded
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func nextConflict() {
        let indices = conflictBlockIndices
        guard !indices.isEmpty else {
            currentConflictIndex = 0
            return
        }

        currentConflictIndex = min(currentConflictIndex + 1, indices.count - 1)
    }

    public func previousConflict() {
        guard !conflictBlockIndices.isEmpty else {
            currentConflictIndex = 0
            return
        }

        currentConflictIndex = max(currentConflictIndex - 1, 0)
    }

    public func resolveCurrent(_ resolution: ConflictHunk.Resolution) {
        resolveConflict(atConflictIndex: currentConflictIndex, resolution: resolution)
    }

    public func resolveConflict(atConflictIndex index: Int, resolution: ConflictHunk.Resolution) {
        let indices = conflictBlockIndices
        guard indices.indices.contains(index) else {
            return
        }

        let blockIndex = indices[index]
        guard case .conflict(let hunk) = blocks[blockIndex] else {
            return
        }

        blocks[blockIndex] = .conflict(ConflictHunk(
            baseLines: hunk.baseLines,
            mineLines: hunk.mineLines,
            theirsLines: hunk.theirsLines,
            resolution: resolution
        ))
    }

    public func mergedText() -> String? {
        guard let mergedLines = MergeEngine.mergedLines(from: blocks) else {
            return nil
        }

        let text = mergedLines.joined(separator: "\n")
        return preservesTrailingNewline ? text + "\n" : text
    }

    public func saveResolved() async {
        guard let conflict, let workingCopy else {
            state = .error("missingConflict")
            return
        }

        guard canSaveResolved, let mergedText = mergedText() else {
            state = .error("unresolvedConflicts")
            return
        }

        state = .saving

        do {
            try await provider.saveResolution(conflict, wc: workingCopy, mergedText: mergedText)
            state = .saved
        } catch {
            state = .error(String(describing: error))
        }
    }

    private static func lines(_ text: String) -> [Substring] {
        let splitLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return text.hasSuffix("\n") ? Array(splitLines.dropLast()) : splitLines
    }
}

extension ConflictService: TextConflictLoading {}
extension ConflictService: ConflictResolutionSaving {}
