import Foundation
import Observation

public protocol MergeProviding: Sendable {
    func merge(
        wc: URL,
        source: String,
        range: RevisionRange?,
        dryRun: Bool,
        auth: Credential?
    ) async throws -> MergeSummary

    func mergeTwoTrees(
        wc: URL,
        from: String,
        to: String,
        dryRun: Bool,
        auth: Credential?
    ) async throws -> MergeSummary

    func mergeReintegrate(
        wc: URL,
        source: String,
        dryRun: Bool,
        auth: Credential?
    ) async throws -> MergeSummary

    func mergeRevisionTo(
        wc: URL,
        source: String,
        revision: Revision,
        dryRun: Bool,
        auth: Credential?
    ) async throws -> MergeSummary

    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String
    func diffBetweenPaths(wc: URL, oldPath: String, newPath: String) async throws -> String
}

public extension MergeProviding {
    func mergeReintegrate(wc: URL, source: String, dryRun: Bool, auth: Credential?) async throws -> MergeSummary {
        try await merge(wc: wc, source: source, range: nil, dryRun: dryRun, auth: auth)
    }

    func mergeRevisionTo(wc: URL, source: String, revision: Revision, dryRun: Bool, auth: Credential?) async throws -> MergeSummary {
        guard revision.value > 0 else {
            throw SvnError.other(code: nil, stderr: "revision must be greater than zero")
        }
        return try await merge(
            wc: wc,
            source: source,
            range: RevisionRange(start: Revision(revision.value - 1), end: revision),
            dryRun: dryRun,
            auth: auth
        )
    }
}

public enum MergeWizardState: Equatable, Sendable {
    case idle
    case previewing
    case previewReady(MergeSummary)
    case diffPreviewing
    case diffReady
    case merging
    case completed(MergeSummary)
    case error(String)
}

@MainActor
@Observable
public final class MergeWizardViewModel {
    private let provider: any MergeProviding

    public private(set) var state: MergeWizardState = .idle
    public private(set) var previewSummary: MergeSummary?
    public private(set) var mergeSummary: MergeSummary?
    public private(set) var unifiedDiff: String?

    public init(provider: any MergeProviding) {
        self.provider = provider
    }

    public func preview(
        wc: URL,
        source: String,
        range: RevisionRange? = nil,
        auth: Credential? = nil
    ) async {
        await runMerge(
            wc: wc,
            source: source,
            range: range,
            auth: auth,
            dryRun: true
        )
    }

    public func merge(
        wc: URL,
        source: String,
        range: RevisionRange? = nil,
        auth: Credential? = nil
    ) async {
        await runMerge(
            wc: wc,
            source: source,
            range: range,
            auth: auth,
            dryRun: false
        )
    }

    public func previewTwoTrees(
        wc: URL,
        from: String,
        to: String,
        auth: Credential? = nil
    ) async {
        let from = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else {
            state = .error("emptyMergeSource")
            return
        }
        state = .previewing
        do {
            let summary = try await provider.mergeTwoTrees(
                wc: wc, from: from, to: to, dryRun: true, auth: auth
            )
            previewSummary = summary
            state = .previewReady(summary)
        } catch {
            previewSummary = nil
            state = .error(String(describing: error))
        }
    }

    public func mergeTwoTrees(
        wc: URL,
        from: String,
        to: String,
        auth: Credential? = nil
    ) async {
        let from = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else {
            state = .error("emptyMergeSource")
            return
        }
        state = .merging
        do {
            let summary = try await provider.mergeTwoTrees(
                wc: wc, from: from, to: to, dryRun: false, auth: auth
            )
            mergeSummary = summary
            state = .completed(summary)
        } catch {
            mergeSummary = nil
            state = .error(String(describing: error))
        }
    }

    public func previewReintegrate(wc: URL, source: String, auth: Credential? = nil) async {
        await runSpecialMerge(wc: wc, source: source, revision: nil, dryRun: true, auth: auth)
    }

    public func reintegrate(wc: URL, source: String, auth: Credential? = nil) async {
        await runSpecialMerge(wc: wc, source: source, revision: nil, dryRun: false, auth: auth)
    }

    public func previewMergeRevisionTo(
        wc: URL,
        source: String,
        revision: Revision,
        auth: Credential? = nil
    ) async {
        await runSpecialMerge(wc: wc, source: source, revision: revision, dryRun: true, auth: auth)
    }

    public func mergeRevisionTo(
        wc: URL,
        source: String,
        revision: Revision,
        auth: Credential? = nil
    ) async {
        await runSpecialMerge(wc: wc, source: source, revision: revision, dryRun: false, auth: auth)
    }

    public func previewUnifiedDiff(
        wc: URL,
        source: String,
        range: RevisionRange
    ) async {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            state = .error("emptyMergeSource")
            return
        }
        await runDiff {
            try await self.provider.diff(
                wc: wc,
                target: source,
                r1: range.start,
                r2: range.end
            )
        }
    }

    public func previewTwoTreeUnifiedDiff(
        wc: URL,
        from: String,
        to: String
    ) async {
        let from = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty else {
            state = .error("emptyMergeSource")
            return
        }
        await runDiff {
            try await self.provider.diffBetweenPaths(wc: wc, oldPath: from, newPath: to)
        }
    }

    private func runMerge(
        wc: URL,
        source: String,
        range: RevisionRange?,
        auth: Credential?,
        dryRun: Bool
    ) async {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedSource.isEmpty else {
            state = .error("emptyMergeSource")
            return
        }

        state = dryRun ? .previewing : .merging

        do {
            let summary = try await provider.merge(
                wc: wc,
                source: trimmedSource,
                range: range,
                dryRun: dryRun,
                auth: auth
            )

            if dryRun {
                previewSummary = summary
                state = .previewReady(summary)
            } else {
                mergeSummary = summary
                state = .completed(summary)
            }
        } catch {
            if dryRun {
                previewSummary = nil
            } else {
                mergeSummary = nil
            }
            state = .error(String(describing: error))
        }
    }

    private func runDiff(_ operation: @escaping @Sendable () async throws -> String) async {
        state = .diffPreviewing
        do {
            unifiedDiff = try await operation()
            state = .diffReady
        } catch {
            unifiedDiff = nil
            state = .error(String(describing: error))
        }
    }

    private func runSpecialMerge(
        wc: URL,
        source: String,
        revision: Revision?,
        dryRun: Bool,
        auth: Credential?
    ) async {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            state = .error("emptyMergeSource")
            return
        }
        guard revision == nil || revision?.value ?? 0 > 0 else {
            state = .error("invalidMergeRevision")
            return
        }
        state = dryRun ? .previewing : .merging
        do {
            let summary: MergeSummary
            if let revision {
                summary = try await provider.mergeRevisionTo(
                    wc: wc, source: source, revision: revision, dryRun: dryRun, auth: auth
                )
            } else {
                summary = try await provider.mergeReintegrate(
                    wc: wc, source: source, dryRun: dryRun, auth: auth
                )
            }
            if dryRun {
                previewSummary = summary
                state = .previewReady(summary)
            } else {
                mergeSummary = summary
                state = .completed(summary)
            }
        } catch {
            if dryRun {
                previewSummary = nil
            } else {
                mergeSummary = nil
            }
            state = .error(String(describing: error))
        }
    }
}

extension SvnService: MergeProviding {}
