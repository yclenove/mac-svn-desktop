import CoreGraphics
import Foundation
import MacSvnCore
import Observation

@MainActor
@Observable
final class MacSvnWorkingCopyWorkspaceState {
    private(set) var selectedPaths: Set<String> = []
    private(set) var focusedPath: String?
    private(set) var commitPaths: Set<String> = []
    private(set) var commitSelectionWasEdited = false

    func selectRows(_ paths: Set<String>, focusedPath requestedFocus: String?) {
        selectedPaths = paths

        if let requestedFocus, paths.contains(requestedFocus) {
            focusedPath = requestedFocus
        } else if let focusedPath, paths.contains(focusedPath) {
            // Preserve the current Diff while extending a multi-selection.
        } else {
            focusedPath = paths.sorted().first
        }
    }

    func seedFocusedPath(_ path: String) {
        selectedPaths = [path]
        focusedPath = path
    }

    func setCommitSelected(_ selected: Bool, path: String, userInitiated: Bool) {
        if selected {
            commitPaths.insert(path)
        } else {
            commitPaths.remove(path)
        }
        commitSelectionWasEdited = commitSelectionWasEdited || userInitiated
    }

    func replaceCommitPaths(_ paths: Set<String>, userInitiated: Bool) {
        commitPaths = paths
        commitSelectionWasEdited = commitSelectionWasEdited || userInitiated
    }

    func reconcileCommitCandidates(available: Set<String>, defaultSelected: Set<String>) {
        if commitSelectionWasEdited {
            commitPaths.formIntersection(available)
        } else {
            commitPaths = defaultSelected.intersection(available)
        }
    }

    func reconcileVisiblePaths(_ available: Set<String>) {
        selectedPaths.formIntersection(available)
        if let focusedPath, !available.contains(focusedPath) {
            self.focusedPath = selectedPaths.sorted().first
        }
    }

    func resetForWorkingCopy() {
        selectedPaths = []
        focusedPath = nil
        commitPaths = []
        commitSelectionWasEdited = false
    }
}

enum MacSvnWorkspaceWidthClass: Equatable {
    case compact
    case regular

    static func resolve(width: CGFloat) -> Self {
        width < 1_180 ? .compact : .regular
    }
}

enum MacSvnCommitInspectorMetrics {
    static let collapsedHeight: CGFloat = 44
    static let minimumExpandedHeight: CGFloat = 190
    static let idealExpandedHeight: CGFloat = 220
    static let maximumExpandedHeight: CGFloat = 260
}

enum MacSvnEmbeddedDiffPresentation: Equatable {
    case noSelection
    case loading(path: String)
    case loaded(path: String)
    case noChanges(path: String)
    case binary(path: String, details: BinaryFileDetails?)
    case error(path: String, message: String)

    static func resolve(path: String?, state: DiffViewState, diffText: String) -> Self {
        guard let path else { return .noSelection }

        switch state {
        case .idle, .loading:
            return .loading(path: path)
        case .loaded:
            return diffText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .noChanges(path: path)
                : .loaded(path: path)
        case .binaryUnsupported(let details):
            return .binary(path: path, details: details)
        case .error(let message):
            return .error(path: path, message: message)
        }
    }
}
