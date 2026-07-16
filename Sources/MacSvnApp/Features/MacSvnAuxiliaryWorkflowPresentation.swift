import Foundation
import SwiftUI
import MacSvnCore

enum MacSvnAuxiliaryWorkflowMetrics {
    static let toolbarHeight: CGFloat = 48
    static let masterWidth: CGFloat = 300
    static let masterMinimumWidth: CGFloat = 280
    static let masterMaximumWidth: CGFloat = 340
    static let detailMinimumWidth: CGFloat = 420
    static let feedbackHeight: CGFloat = 30
}

enum MacSvnAuxiliaryPathPresentation {
    static func relativePath(_ path: String, workingCopy: URL) -> String {
        guard (path as NSString).isAbsolutePath else { return path }

        let rootPath = workingCopy.standardizedFileURL.path
        let targetPath = URL(fileURLWithPath: path).standardizedFileURL.path
        if targetPath == rootPath { return "." }

        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard targetPath.hasPrefix(rootPrefix) else { return path }
        return String(targetPath.dropFirst(rootPrefix.count))
    }

    static func title(for path: String) -> String {
        path == "." ? "工作副本根目录" : path
    }
}

enum MacSvnLockActionPresentation {
    static func eligibleReleasePaths(selected: [String], locks: [SvnLock]) -> [String] {
        guard !locks.isEmpty else { return [] }
        return LockActionPolicy.pathsEligibleForRelease(selected: selected, locks: locks)
    }
}

enum MacSvnAuxiliaryLatestRequestPolicy {
    static func shouldApply(
        requestID: UUID,
        currentRequestID: UUID?,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled && requestID == currentRequestID
    }
}

@MainActor
final class MacSvnAuxiliaryLatestRequestRunner {
    private var task: Task<Void, Never>?
    private(set) var currentRequestID: UUID?

    @discardableResult
    func enqueue(
        debounce: Duration = .milliseconds(80),
        operation: @escaping @Sendable () async throws -> String,
        receive: @escaping @MainActor (UUID, Result<String, Error>) -> Void
    ) -> UUID {
        task?.cancel()
        let requestID = UUID()
        currentRequestID = requestID
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: debounce)
                try Task.checkCancellation()
                let output = try await operation()
                try Task.checkCancellation()
                guard let self, MacSvnAuxiliaryLatestRequestPolicy.shouldApply(
                    requestID: requestID,
                    currentRequestID: self.currentRequestID,
                    isCancelled: Task.isCancelled
                ) else { return }
                receive(requestID, .success(output))
            } catch is CancellationError {
                return
            } catch {
                guard let self, MacSvnAuxiliaryLatestRequestPolicy.shouldApply(
                    requestID: requestID,
                    currentRequestID: self.currentRequestID,
                    isCancelled: Task.isCancelled
                ) else { return }
                receive(requestID, .failure(error))
            }
        }
        return requestID
    }

    func cancel() {
        task?.cancel()
        task = nil
        currentRequestID = nil
    }
}

enum MacSvnShelveLoadOutcome: Equatable {
    case refreshed
    case localFailure(String)
    case officialFailure(String)
}

enum MacSvnShelveOperationOutcome: Equatable {
    case success
    case failure(String)
    case pending
}

enum MacSvnShelveFeedbackPresentation {
    static func loadOutcome(
        state: ShelveViewState?,
        officialError: String?
    ) -> MacSvnShelveLoadOutcome {
        if case .error(let message) = state {
            return .localFailure(message)
        }
        if let officialError {
            return .officialFailure(officialError)
        }
        return .refreshed
    }

    static func operationOutcome(
        state: ShelveViewState?,
        expected: ShelveOperation
    ) -> MacSvnShelveOperationOutcome {
        switch state {
        case .completed(let completed) where completed == expected:
            return .success
        case .error(let message):
            return .failure(message)
        default:
            return .pending
        }
    }
}

struct MacSvnAuxiliaryPathList: View {
    let paths: [String]
    @Binding var selection: Set<String>
    @Binding var searchText: String
    var allowsMultiple = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("筛选目标", text: $searchText)
                    .textFieldStyle(.plain)
                Text("\(filteredPaths.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(filteredPaths.count) 个目标")
            }
            .padding(.horizontal, 10)
            .frame(height: 36)

            Divider()

            if filteredPaths.isEmpty {
                ContentUnavailableView("没有匹配的目标", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(filteredPaths, id: \.self) { path in
                        Text(MacSvnAuxiliaryPathPresentation.title(for: path))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(path)
                            .tag(path)
                    }
                }
                .listStyle(.inset)
            }
        }
        .onChange(of: selection) { oldValue, newValue in
            guard !allowsMultiple, newValue.count > 1 else { return }
            let newlySelected = newValue.subtracting(oldValue).first
                ?? newValue.sorted().last
            selection = newlySelected.map { [$0] } ?? []
        }
    }

    private var filteredPaths: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return paths }
        return paths.filter {
            MacSvnAuxiliaryPathPresentation.title(for: $0)
                .localizedCaseInsensitiveContains(query)
        }
    }
}
