import Foundation

public struct QuickLookDiffPreview: Equatable, Sendable {
    public let workingCopy: URL
    public let fileURL: URL
    public let target: String
    public let diffText: String
    public let lines: [UnifiedDiffLine]

    public init(workingCopy: URL, fileURL: URL, target: String, diffText: String, lines: [UnifiedDiffLine]) {
        self.workingCopy = workingCopy
        self.fileURL = fileURL
        self.target = target
        self.diffText = diffText
        self.lines = lines
    }
}

public enum QuickLookDiffUnsupportedReason: Equatable, Sendable {
    case outsideWorkingCopy
    case directory
    case missing
    case binary(BinaryFileDetails?)
}

public enum QuickLookDiffPreviewResult: Equatable, Sendable {
    case preview(QuickLookDiffPreview)
    case unsupported(QuickLookDiffUnsupportedReason)
    case error(String)
}

public struct QuickLookDiffPreviewService: Sendable {
    private let workingCopy: URL
    private let diffProvider: any DiffProviding

    public init(workingCopy: URL, diffProvider: any DiffProviding) {
        self.workingCopy = workingCopy.standardizedFileURL
        self.diffProvider = diffProvider
    }

    public func preview(fileURL: URL) async -> QuickLookDiffPreviewResult {
        let standardizedFileURL = fileURL.standardizedFileURL
        guard let target = Self.relativeTarget(for: standardizedFileURL, in: workingCopy) else {
            return .unsupported(.outsideWorkingCopy)
        }

        do {
            let diff = try await diffProvider.diff(wc: workingCopy, target: target, r1: nil, r2: nil)
            return .preview(QuickLookDiffPreview(
                workingCopy: workingCopy,
                fileURL: standardizedFileURL,
                target: target,
                diffText: diff,
                lines: DiffViewModel.parseLines(diff)
            ))
        } catch {
            return .error(String(describing: error))
        }
    }

    private static func relativeTarget(for fileURL: URL, in workingCopy: URL) -> String? {
        let wcPath = workingCopy.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(wcPath + "/") else {
            return nil
        }
        return String(filePath.dropFirst(wcPath.count + 1))
    }
}
