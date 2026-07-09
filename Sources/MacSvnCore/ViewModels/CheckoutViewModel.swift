import Foundation
import Observation

public protocol CheckoutProviding: Sendable {
    func checkout(url: String, to destination: URL, depth: SvnDepth, auth: Credential?) async throws
}

public protocol WorkspaceImporting: Sendable {
    func addExistingWorkingCopy(
        localPath: URL,
        infoProvider: any WorkingCopyInfoProviding,
        username: String?,
        name: String?
    ) async throws -> WorkingCopyRecord
}

public enum CheckoutViewState: Equatable, Sendable {
    case idle
    case checkingOut
    case completed(WorkingCopyRecord)
    case error(String)
}

@MainActor
@Observable
public final class CheckoutViewModel {
    private let checkoutProvider: any CheckoutProviding
    private let workspaceImporter: any WorkspaceImporting
    private let infoProvider: any WorkingCopyInfoProviding

    public private(set) var state: CheckoutViewState = .idle
    public private(set) var importedWorkingCopy: WorkingCopyRecord?

    public init(
        checkoutProvider: any CheckoutProviding,
        workspaceImporter: any WorkspaceImporting,
        infoProvider: any WorkingCopyInfoProviding
    ) {
        self.checkoutProvider = checkoutProvider
        self.workspaceImporter = workspaceImporter
        self.infoProvider = infoProvider
    }

    public func checkout(
        url: String,
        to destination: URL,
        depth: SvnDepth,
        auth: Credential? = nil,
        username: String? = nil,
        name: String? = nil
    ) async {
        state = .checkingOut
        importedWorkingCopy = nil

        do {
            try await checkoutProvider.checkout(url: url, to: destination, depth: depth, auth: auth)
            let record = try await workspaceImporter.addExistingWorkingCopy(
                localPath: destination,
                infoProvider: infoProvider,
                username: username,
                name: name
            )
            importedWorkingCopy = record
            state = .completed(record)
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func checkout(
        entry: RemoteEntry,
        baseURL: String,
        to destination: URL,
        depth: SvnDepth,
        auth: Credential? = nil,
        username: String? = nil,
        name: String? = nil
    ) async {
        guard entry.kind == .directory else {
            importedWorkingCopy = nil
            state = .error("checkoutRequiresDirectory")
            return
        }

        await checkout(
            url: remoteURL(baseURL: baseURL, entryPath: entry.path),
            to: destination,
            depth: depth,
            auth: auth,
            username: username,
            name: name
        )
    }

    private func remoteURL(baseURL: String, entryPath: String) -> String {
        if baseURL.hasSuffix("/") {
            return baseURL + entryPath
        }

        return baseURL + "/" + entryPath
    }
}

extension SvnService: CheckoutProviding {}
extension WorkspaceStore: WorkspaceImporting {}
