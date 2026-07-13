import Foundation
import Observation

public protocol BranchSwitchProviding: Sendable {
    func switchTo(
        wc: URL,
        url: String,
        revision: Revision?,
        auth: Credential?,
        allowLocalChanges: Bool
    ) async throws -> UpdateSummary
}

public enum BranchSwitchState: Equatable, Sendable {
    case idle
    case switching
    case confirmationRequired(paths: [String])
    case completed(UpdateSummary)
    case error(String)
}

@MainActor
@Observable
public final class BranchSwitchViewModel {
    private struct PendingSwitch: Sendable {
        let wc: URL
        let url: String
        let revision: Revision?
        let auth: Credential?
    }

    private let provider: any BranchSwitchProviding
    private var pendingSwitch: PendingSwitch?

    public private(set) var state: BranchSwitchState = .idle
    public private(set) var lastSummary: UpdateSummary?

    public init(provider: any BranchSwitchProviding) {
        self.provider = provider
    }

    public func switchTo(
        wc: URL,
        url: String,
        revision: Revision? = nil,
        auth: Credential? = nil
    ) async {
        pendingSwitch = PendingSwitch(wc: wc, url: url, revision: revision, auth: auth)
        await performSwitch(
            wc: wc,
            url: url,
            revision: revision,
            auth: auth,
            allowLocalChanges: false
        )
    }

    public func confirmSwitchWithLocalChanges() async {
        guard let pendingSwitch else {
            state = .idle
            return
        }

        await performSwitch(
            wc: pendingSwitch.wc,
            url: pendingSwitch.url,
            revision: pendingSwitch.revision,
            auth: pendingSwitch.auth,
            allowLocalChanges: true
        )
    }

    private func performSwitch(
        wc: URL,
        url: String,
        revision: Revision?,
        auth: Credential?,
        allowLocalChanges: Bool
    ) async {
        state = .switching

        do {
            let summary = try await provider.switchTo(
                wc: wc,
                url: url,
                revision: revision,
                auth: auth,
                allowLocalChanges: allowLocalChanges
            )
            pendingSwitch = nil
            lastSummary = summary
            state = .completed(summary)
        } catch SvnServiceError.localChangesPreventSwitch(let paths) {
            lastSummary = nil
            state = .confirmationRequired(paths: paths)
        } catch {
            pendingSwitch = nil
            lastSummary = nil
            state = .error(String(describing: error))
        }
    }
}

extension SvnService: BranchSwitchProviding {}
