import Foundation
import Observation

public protocol TextConflictLoading: Sendable {
    func loadTextConflict(_ conflict: ConflictInfo) async throws -> (base: String, mine: String, theirs: String)
}

public protocol ConflictResolutionSaving: Sendable {
    func saveResolution(_ conflict: ConflictInfo, wc: URL, mergedText: String) async throws
}

public protocol WholeFileConflictResolving: Sendable {
    func resolveWholeFile(_ conflict: ConflictInfo, wc: URL, accept: ResolveAccept) async throws
}

public enum MergeEditorState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case saving
    case saved
    case error(String)
}

public enum AIConflictAssistViewState: Equatable, Sendable {
    case idle
    case suggesting
    case suggested(AIConflictAssistSuggestion)
    case previewed(AIConflictAssistPreview)
    case error(String)
}

@MainActor
@Observable
public final class MergeEditorViewModel {
    private let provider: any TextConflictLoading & ConflictResolutionSaving & WholeFileConflictResolving
    private let aiConflictAssistant: (any AIConflictAssisting)?
    private var preservesTrailingNewline = false
    private var loadedBlocksSnapshot: [MergeBlock] = []
    private var activeAIRequestID: UUID?

    public private(set) var state: MergeEditorState = .idle
    public private(set) var aiConflictAssistState: AIConflictAssistViewState = .idle
    public private(set) var conflict: ConflictInfo?
    public private(set) var workingCopy: URL?
    public private(set) var blocks: [MergeBlock] = []
    public private(set) var currentConflictIndex = 0
    public private(set) var hasUnsavedChanges = false
    public private(set) var aiConflictSuggestion: AIConflictAssistSuggestion?
    public private(set) var aiConflictPreview: AIConflictAssistPreview?

    public init(
        provider: any TextConflictLoading & ConflictResolutionSaving & WholeFileConflictResolving,
        aiConflictAssistant: (any AIConflictAssisting)? = nil
    ) {
        self.provider = provider
        self.aiConflictAssistant = aiConflictAssistant
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

    public var shouldWarnBeforeClose: Bool {
        hasUnsavedChanges
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
        loadedBlocksSnapshot = []
        currentConflictIndex = 0
        hasUnsavedChanges = false
        aiConflictAssistState = .idle
        aiConflictSuggestion = nil
        aiConflictPreview = nil
        activeAIRequestID = nil

        do {
            let text = try await provider.loadTextConflict(conflict)
            preservesTrailingNewline = text.mine.hasSuffix("\n")
            blocks = MergeEngine.merge3(
                base: Self.lines(text.base),
                mine: Self.lines(text.mine),
                theirs: Self.lines(text.theirs)
            )
            loadedBlocksSnapshot = blocks
            currentConflictIndex = conflictBlockIndices.isEmpty ? 0 : 0
            hasUnsavedChanges = false
            state = .loaded
        } catch {
            loadedBlocksSnapshot = []
            hasUnsavedChanges = false
            state = .error(String(describing: error))
        }
    }

    public func requestAIResolutionForCurrentConflict(
        privacySettings: AIPrivacySettings = AIPrivacySettings()
    ) async {
        guard let aiConflictAssistant else {
            aiConflictAssistState = .error("aiConflictAssistantUnavailable")
            return
        }

        guard let conflict,
              let blockIndex = currentBlockIndex,
              case .conflict(let hunk) = blocks[blockIndex] else {
            aiConflictAssistState = .error("missingConflict")
            return
        }

        let requestID = UUID()
        let requestedConflict = conflict
        let requestedConflictIndex = currentConflictIndex
        let requestedBlockIndex = blockIndex
        let requestedBlocks = blocks
        activeAIRequestID = requestID
        aiConflictAssistState = .suggesting

        do {
            let suggestion = try await aiConflictAssistant.suggestResolution(
                context: AIConflictAssistContext(
                    path: conflict.path,
                    conflictIndex: currentConflictIndex,
                    baseLines: hunk.baseLines,
                    mineLines: hunk.mineLines,
                    theirsLines: hunk.theirsLines,
                    leadingContext: leadingContext(before: blockIndex),
                    trailingContext: trailingContext(after: blockIndex)
                ),
                privacySettings: privacySettings
            )
            guard activeAIRequestID == requestID,
                  self.conflict == requestedConflict,
                  currentConflictIndex == requestedConflictIndex,
                  currentBlockIndex == requestedBlockIndex,
                  blocks == requestedBlocks else {
                if activeAIRequestID == requestID {
                    activeAIRequestID = nil
                    aiConflictAssistState = .idle
                }
                return
            }
            activeAIRequestID = nil
            resolveConflict(
                atConflictIndex: requestedConflictIndex,
                resolution: .manual(lines: suggestion.mergedLines)
            )
            aiConflictSuggestion = suggestion
            aiConflictPreview = nil
            aiConflictAssistState = .suggested(suggestion)
        } catch {
            guard activeAIRequestID == requestID else { return }
            activeAIRequestID = nil
            aiConflictAssistState = .error(String(describing: error))
        }
    }

    public func requestAIResolutionPreviewForAllConflicts(
        privacySettings: AIPrivacySettings = AIPrivacySettings()
    ) async {
        guard let aiConflictAssistant else {
            aiConflictAssistState = .error("aiConflictAssistantUnavailable")
            return
        }

        guard let conflict else {
            aiConflictAssistState = .error("missingConflict")
            return
        }

        let contexts = conflictBlockIndices.enumerated().compactMap { conflictIndex, blockIndex -> AIConflictAssistContext? in
            guard case .conflict(let hunk) = blocks[blockIndex] else {
                return nil
            }

            return AIConflictAssistContext(
                path: conflict.path,
                conflictIndex: conflictIndex,
                baseLines: hunk.baseLines,
                mineLines: hunk.mineLines,
                theirsLines: hunk.theirsLines,
                leadingContext: leadingContext(before: blockIndex),
                trailingContext: trailingContext(after: blockIndex)
            )
        }
        guard !contexts.isEmpty else {
            aiConflictAssistState = .error("missingConflict")
            return
        }

        let requestID = UUID()
        let requestedConflict = conflict
        let requestedBlocks = blocks
        activeAIRequestID = requestID
        aiConflictAssistState = .suggesting

        do {
            let preview = try await aiConflictAssistant.suggestResolutions(
                contexts: contexts,
                privacySettings: privacySettings
            )
            guard activeAIRequestID == requestID,
                  self.conflict == requestedConflict,
                  blocks == requestedBlocks else {
                if activeAIRequestID == requestID {
                    activeAIRequestID = nil
                    aiConflictAssistState = .idle
                }
                return
            }
            activeAIRequestID = nil
            aiConflictPreview = preview
            aiConflictSuggestion = nil

            for suggestion in preview.suggestions where suggestion.confidence != .low {
                resolveConflict(
                    atConflictIndex: suggestion.conflictIndex,
                    resolution: .manual(lines: suggestion.mergedLines)
                )
            }

            aiConflictAssistState = .previewed(preview)
        } catch {
            guard activeAIRequestID == requestID else { return }
            activeAIRequestID = nil
            aiConflictAssistState = .error(String(describing: error))
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
        hasUnsavedChanges = true
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
            hasUnsavedChanges = false
            state = .saved
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func resolveWholeFileMine() async {
        await resolveWholeFile(accept: .mineFull)
    }

    public func resolveWholeFileTheirs() async {
        await resolveWholeFile(accept: .theirsFull)
    }

    public func resolveWholeFile(accept: ResolveAccept) async {
        guard let conflict, let workingCopy else {
            state = .error("missingConflict")
            return
        }

        state = .saving

        do {
            try await provider.resolveWholeFile(conflict, wc: workingCopy, accept: accept)
            hasUnsavedChanges = false
            state = .saved
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func discardEdits() {
        blocks = loadedBlocksSnapshot
        let conflictCount = conflictBlockIndices.count
        currentConflictIndex = conflictCount == 0 ? 0 : min(currentConflictIndex, conflictCount - 1)
        hasUnsavedChanges = false

        if case .error = state {
            state = .loaded
        }
    }

    private static func lines(_ text: String) -> [Substring] {
        let splitLines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return text.hasSuffix("\n") ? Array(splitLines.dropLast()) : splitLines
    }

    private func leadingContext(before blockIndex: Int) -> [String] {
        guard blockIndex > 0 else {
            return []
        }

        for index in stride(from: blockIndex - 1, through: 0, by: -1) {
            if case .stable(let lines) = blocks[index] {
                return Array(lines.suffix(3))
            }
        }

        return []
    }

    private func trailingContext(after blockIndex: Int) -> [String] {
        guard blockIndex + 1 < blocks.count else {
            return []
        }

        for index in (blockIndex + 1)..<blocks.count {
            if case .stable(let lines) = blocks[index] {
                return Array(lines.prefix(3))
            }
        }

        return []
    }
}

extension ConflictService: TextConflictLoading {}
extension ConflictService: ConflictResolutionSaving {}
extension ConflictService: WholeFileConflictResolving {}
