import Foundation
import Observation

public enum PatchOperation: Equatable, Sendable {
    case create
    case apply
}

public enum PatchViewState: Equatable, Sendable {
    case idle
    case running(PatchOperation)
    case completed(PatchOperation)
    case error(String)
}

public protocol PatchProviding: Sendable {
    func createPatch(wc: URL, paths: [String], to destination: URL) async throws
    func applyPatch(wc: URL, patchFile: URL) async throws
}

@MainActor
@Observable
public final class PatchViewModel {
    private let workingCopy: URL
    private let provider: any PatchProviding

    public private(set) var state: PatchViewState = .idle

    public init(workingCopy: URL, provider: any PatchProviding) {
        self.workingCopy = workingCopy
        self.provider = provider
    }

    public func create(paths: [String], to destination: URL) async {
        do {
            _ = try PatchPathPolicy.validate(paths)
        } catch {
            state = .error(String(describing: error))
            return
        }

        state = .running(.create)
        do {
            try await provider.createPatch(wc: workingCopy, paths: paths, to: destination)
            state = .completed(.create)
        } catch {
            state = .error(String(describing: error))
        }
    }

    public func apply(patchFile: URL) async {
        guard FileManager.default.fileExists(atPath: patchFile.path) else {
            state = .error("patchFileNotFound")
            return
        }

        state = .running(.apply)
        do {
            try await provider.applyPatch(wc: workingCopy, patchFile: patchFile)
            state = .completed(.apply)
        } catch {
            state = .error(String(describing: error))
        }
    }
}

extension SvnService: PatchProviding {}
