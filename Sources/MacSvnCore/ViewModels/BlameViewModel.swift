import Foundation
import Observation

public protocol BlameProviding: Sendable {
    func blame(wc: URL, target: String) async throws -> [BlameLine]
}

public protocol BlameLogProviding: Sendable {
    func logForBlame(wc: URL, target: String, revision: Revision) async throws -> LogEntry?
}

public protocol BlameRangeProviding: Sendable {
    func blame(
        wc: URL,
        target: String,
        startRevision: Revision?,
        endRevision: Revision?
    ) async throws -> [BlameLine]
}

public enum BlameViewState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

@MainActor
@Observable
public final class BlameViewModel {
    private let workingCopy: URL
    private let target: String
    private let provider: any BlameProviding
    private let logProvider: (any BlameLogProviding)?
    private let rangeProvider: (any BlameRangeProviding)?

    public private(set) var state: BlameViewState = .idle
    public private(set) var lines: [BlameLine] = []
    public private(set) var selectedRevision: Revision?
    public private(set) var hoveredLineNumber: Int?
    public private(set) var hoveredLog: LogEntry?
    public private(set) var hoverLogError: String?

    public init(
        workingCopy: URL,
        target: String,
        provider: any BlameProviding,
        logProvider: (any BlameLogProviding)? = nil,
        rangeProvider: (any BlameRangeProviding)? = nil
    ) {
        self.workingCopy = workingCopy
        self.target = target
        self.provider = provider
        self.logProvider = logProvider
        self.rangeProvider = rangeProvider
    }

    public func load() async {
        await load(startRevision: nil, endRevision: nil)
    }

    public func load(startRevision: Revision?, endRevision: Revision?) async {
        state = .loading
        lines = []
        selectedRevision = nil
        hoveredLineNumber = nil
        hoveredLog = nil
        hoverLogError = nil

        do {
            if let rangeProvider, startRevision != nil || endRevision != nil {
                lines = try await rangeProvider.blame(
                    wc: workingCopy,
                    target: target,
                    startRevision: startRevision,
                    endRevision: endRevision
                )
            } else {
                lines = try await provider.blame(wc: workingCopy, target: target)
            }
            state = .loaded
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func selectLine(_ lineNumber: Int) {
        selectedRevision = lines.first { $0.lineNumber == lineNumber }?.revision
    }

    public func loadRevisionDetails(for lineNumber: Int) async {
        hoveredLineNumber = lineNumber
        hoveredLog = nil
        hoverLogError = nil
        guard let revision = lines.first(where: { $0.lineNumber == lineNumber })?.revision,
              let logProvider
        else { return }

        do {
            let entry = try await logProvider.logForBlame(wc: workingCopy, target: target, revision: revision)
            guard hoveredLineNumber == lineNumber else { return }
            hoveredLog = entry
        } catch {
            guard hoveredLineNumber == lineNumber else { return }
            hoverLogError = String(describing: error)
        }
    }

    public func clearRevisionDetails(for lineNumber: Int) {
        guard hoveredLineNumber == lineNumber else { return }
        hoveredLineNumber = nil
        hoveredLog = nil
        hoverLogError = nil
    }
}

extension SvnService: BlameProviding {}
extension SvnService: BlameRangeProviding {}
extension SvnService: BlameLogProviding {
    public func logForBlame(wc: URL, target: String, revision: Revision) async throws -> LogEntry? {
        let entries = try await log(
            wc: wc,
            target: target,
            from: revision,
            batch: 1,
            verbose: true,
            stopOnCopy: false
        )
        return entries.first(where: { $0.revision == revision }) ?? entries.first
    }
}
