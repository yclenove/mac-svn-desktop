import Foundation
import Observation

public protocol DiffProviding: Sendable {
    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String
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

@MainActor
@Observable
public final class DiffViewModel {
    private let workingCopy: URL
    private let diffProvider: any DiffProviding

    public private(set) var state: DiffViewState = .idle
    public private(set) var diffText = ""
    public private(set) var lines: [UnifiedDiffLine] = []

    public init(workingCopy: URL, diffProvider: any DiffProviding) {
        self.workingCopy = workingCopy
        self.diffProvider = diffProvider
    }

    public func load(target: String, r1: Revision? = nil, r2: Revision? = nil) async {
        state = .loading

        do {
            let rawDiff = try await diffProvider.diff(wc: workingCopy, target: target, r1: r1, r2: r2)
            diffText = rawDiff

            if Self.isBinaryUnsupportedDiff(rawDiff) {
                lines = []
                state = .binaryUnsupported(binaryDetails(for: target))
                return
            }

            lines = Self.parseLines(rawDiff)
            state = .loaded
        } catch {
            diffText = ""
            lines = []
            state = .error(String(describing: error))
        }
    }

    public static func parseLines(_ diff: String) -> [UnifiedDiffLine] {
        diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { index, line in
            let text = String(line)
            return UnifiedDiffLine(id: index, text: text, kind: classify(text))
        }
    }

    private static func classify(_ line: String) -> UnifiedDiffLineKind {
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

    private static func isBinaryUnsupportedDiff(_ diff: String) -> Bool {
        let normalized = diff.lowercased()
        return (normalized.contains("cannot display") && normalized.contains("binary"))
            || normalized.contains("binary files")
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
