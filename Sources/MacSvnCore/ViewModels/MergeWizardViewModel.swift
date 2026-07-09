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
}

public enum MergeWizardState: Equatable, Sendable {
    case idle
    case previewing
    case previewReady(MergeSummary)
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
}

extension SvnService: MergeProviding {}
