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

enum MacSvnAuxiliaryFeedbackColorRole: Equatable {
    case accent
    case positive
    case caution
    case negative
}

enum MacSvnAuxiliaryFeedbackKind: Equatable {
    case progress
    case success
    case warning
    case failure

    var systemImage: String {
        switch self {
        case .progress: "arrow.triangle.2.circlepath"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        }
    }

    var colorRole: MacSvnAuxiliaryFeedbackColorRole {
        switch self {
        case .progress: .accent
        case .success: .positive
        case .warning: .caution
        case .failure: .negative
        }
    }
}

struct MacSvnAuxiliaryFeedback: Equatable {
    typealias Kind = MacSvnAuxiliaryFeedbackKind

    let kind: Kind
    let message: String
    let diagnostic: String?

    static func localized(
        kind: Kind,
        message: String.LocalizationValue,
        locale: Locale,
        bundle: LocalizedStringResource.BundleDescription = .main,
        diagnostic: String?
    ) -> Self {
        let resource = LocalizedStringResource(
            message,
            locale: locale,
            bundle: bundle
        )
        return Self(
            kind: kind,
            message: String(localized: resource),
            diagnostic: diagnostic
        )
    }
}

enum MacSvnAuxiliaryErrorSummaryPresentation {
    static func message(
        _ rawMessage: String,
        locale: Locale,
        bundle: LocalizedStringResource.BundleDescription = .main
    ) -> String {
        let summary = MacSvnCoreModeErrorPresentation.message(rawMessage)
        let resource = LocalizedStringResource(
            String.LocalizationValue(summary),
            locale: locale,
            bundle: bundle
        )
        return String(localized: resource)
    }
}

enum MacSvnAuxiliaryDismissalDecision: Equatable {
    case blocked
    case confirmDiscard
    case dismiss

    var preventsDismissal: Bool {
        self != .dismiss
    }
}

enum MacSvnAuxiliaryDismissalPolicy {
    static func decision(isBusy: Bool, isDirty: Bool) -> MacSvnAuxiliaryDismissalDecision {
        if isBusy { return .blocked }
        if isDirty { return .confirmDiscard }
        return .dismiss
    }
}

enum MacSvnGetLockPresentationPolicy {
    static func shouldPresent(
        userPreference: Bool,
        requiresMessage: Bool,
        containsDirectory: Bool
    ) -> Bool {
        userPreference || requiresMessage || containsDirectory
    }
}

struct MacSvnInlineFeedbackView: View {
    let feedback: MacSvnAuxiliaryFeedback?
    var truncationMode: Text.TruncationMode = .tail

    var body: some View {
        Group {
            if let feedback {
                feedbackContent(feedback)
            } else {
                Color.clear
            }
        }
        .padding(.horizontal, 16)
        .frame(height: MacSvnAuxiliaryWorkflowMetrics.feedbackHeight)
        .background(Color.secondary.opacity(0.04))
    }

    private func feedbackContent(_ feedback: MacSvnAuxiliaryFeedback) -> some View {
        HStack(spacing: 6) {
            Image(systemName: feedback.kind.systemImage)
                .foregroundStyle(feedback.kind.color)
                .accessibilityHidden(true)
            Text(verbatim: feedback.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(truncationMode)
            Spacer(minLength: 0)
        }
        .help(feedback.diagnostic ?? feedback.message)
    }
}

enum MacSvnPropertyLoadFeedbackPresentation {
    static func feedback(
        propertyState: PropertyViewState?,
        infoDiagnostic: String?,
        statusDiagnostic: String?,
        projectPropertyDiagnostic: String? = nil,
        locale: Locale,
        bundle: LocalizedStringResource.BundleDescription = .main
    ) -> MacSvnAuxiliaryFeedback? {
        if case .error(let diagnostic) = propertyState {
            let presented = MacSvnAuxiliaryErrorSummaryPresentation.message(
                diagnostic,
                locale: locale,
                bundle: bundle
            )
            return .localized(
                kind: .failure,
                message: "属性操作失败：\(presented)",
                locale: locale,
                bundle: bundle,
                diagnostic: diagnostic
            )
        }

        switch (infoDiagnostic, statusDiagnostic, projectPropertyDiagnostic) {
        case let (info?, status?, project?):
            let presentedInfo = MacSvnAuxiliaryErrorSummaryPresentation.message(info, locale: locale, bundle: bundle)
            let presentedStatus = MacSvnAuxiliaryErrorSummaryPresentation.message(status, locale: locale, bundle: bundle)
            let presentedProject = MacSvnAuxiliaryErrorSummaryPresentation.message(project, locale: locale, bundle: bundle)
            return .localized(
                kind: .warning,
                message: "SVN 信息、状态与项目属性读取失败：\(presentedInfo)；\(presentedStatus)；\(presentedProject)",
                locale: locale,
                bundle: bundle,
                diagnostic: "\(info)\n\(status)\n\(project)"
            )
        case let (info?, status?, nil):
            let presentedInfo = MacSvnAuxiliaryErrorSummaryPresentation.message(info, locale: locale, bundle: bundle)
            let presentedStatus = MacSvnAuxiliaryErrorSummaryPresentation.message(status, locale: locale, bundle: bundle)
            return .localized(
                kind: .warning,
                message: "SVN 信息与状态读取失败：\(presentedInfo)；\(presentedStatus)",
                locale: locale,
                bundle: bundle,
                diagnostic: "\(info)\n\(status)"
            )
        case let (info?, nil, project?):
            let presentedInfo = MacSvnAuxiliaryErrorSummaryPresentation.message(info, locale: locale, bundle: bundle)
            let presentedProject = MacSvnAuxiliaryErrorSummaryPresentation.message(project, locale: locale, bundle: bundle)
            return .localized(
                kind: .warning,
                message: "SVN 信息与项目属性读取失败：\(presentedInfo)；\(presentedProject)",
                locale: locale,
                bundle: bundle,
                diagnostic: "\(info)\n\(project)"
            )
        case let (nil, status?, project?):
            let presentedStatus = MacSvnAuxiliaryErrorSummaryPresentation.message(status, locale: locale, bundle: bundle)
            let presentedProject = MacSvnAuxiliaryErrorSummaryPresentation.message(project, locale: locale, bundle: bundle)
            return .localized(
                kind: .warning,
                message: "SVN 状态与项目属性读取失败：\(presentedStatus)；\(presentedProject)",
                locale: locale,
                bundle: bundle,
                diagnostic: "\(status)\n\(project)"
            )
        case let (info?, nil, nil):
            let presented = MacSvnAuxiliaryErrorSummaryPresentation.message(info, locale: locale, bundle: bundle)
            return .localized(
                kind: .warning,
                message: "SVN 信息读取失败：\(presented)",
                locale: locale,
                bundle: bundle,
                diagnostic: info
            )
        case let (nil, status?, nil):
            let presented = MacSvnAuxiliaryErrorSummaryPresentation.message(status, locale: locale, bundle: bundle)
            return .localized(
                kind: .warning,
                message: "SVN 状态读取失败：\(presented)",
                locale: locale,
                bundle: bundle,
                diagnostic: status
            )
        case let (nil, nil, project?):
            let presented = MacSvnAuxiliaryErrorSummaryPresentation.message(project, locale: locale, bundle: bundle)
            return .localized(
                kind: .warning,
                message: "项目属性读取失败：\(presented)",
                locale: locale,
                bundle: bundle,
                diagnostic: project
            )
        case (nil, nil, nil):
            return nil
        }
    }
}

enum MacSvnLockFeedbackPresentation {
    static func feedback(
        state: LockViewState?,
        projectPropertyLoadError: String?,
        projectPropertyLoadDiagnostic: String? = nil,
        lockCount: Int,
        fallback: MacSvnAuxiliaryFeedback?,
        locale: Locale,
        bundle: LocalizedStringResource.BundleDescription = .main
    ) -> MacSvnAuxiliaryFeedback? {
        switch state {
        case .error(let diagnostic):
            if diagnostic == "projectPropertiesLoadFailed" {
                if let projectPropertyLoadDiagnostic {
                    let presented = MacSvnAuxiliaryErrorSummaryPresentation.message(
                        projectPropertyLoadDiagnostic,
                        locale: locale,
                        bundle: bundle
                    )
                    return .localized(
                        kind: .failure,
                        message: "项目属性读取失败：\(presented)",
                        locale: locale,
                        bundle: bundle,
                        diagnostic: projectPropertyLoadDiagnostic
                    )
                }
                return .localized(
                    kind: .failure,
                    message: "项目属性读取失败。请刷新或重新选择目标后重试。",
                    locale: locale,
                    bundle: bundle,
                    diagnostic: nil
                )
            }
            let presented = MacSvnAuxiliaryErrorSummaryPresentation.message(
                diagnostic,
                locale: locale,
                bundle: bundle
            )
            return .localized(
                kind: .failure,
                message: "锁操作失败：\(presented)",
                locale: locale,
                bundle: bundle,
                diagnostic: diagnostic
            )
        case .loading:
            return .localized(kind: .progress, message: "正在刷新锁记录", locale: locale, bundle: bundle, diagnostic: nil)
        case .locking:
            return .localized(kind: .progress, message: "正在获取锁", locale: locale, bundle: bundle, diagnostic: nil)
        case .unlocking:
            return .localized(kind: .progress, message: "正在释放锁", locale: locale, bundle: bundle, diagnostic: nil)
        default:
            break
        }

        if projectPropertyLoadError != nil {
            return .localized(
                kind: .warning,
                message: "项目属性读取失败，已阻止获取锁。请刷新或重新选择目标后重试。",
                locale: locale,
                bundle: bundle,
                diagnostic: projectPropertyLoadDiagnostic
            )
        }

        switch state {
        case .confirmationRequired(.stealLock, let paths):
            return .localized(
                kind: .warning,
                message: "等待确认夺锁：\(paths.count) 项",
                locale: locale,
                bundle: bundle,
                diagnostic: nil
            )
        case .confirmationRequired(.breakLock, let paths):
            return .localized(
                kind: .warning,
                message: "等待确认打断锁：\(paths.count) 项",
                locale: locale,
                bundle: bundle,
                diagnostic: nil
            )
        case .confirmationRequired:
            return .localized(kind: .warning, message: "等待确认", locale: locale, bundle: bundle, diagnostic: nil)
        case .loaded:
            return lockCount == 0
                ? .localized(kind: .success, message: "没有锁记录", locale: locale, bundle: bundle, diagnostic: nil)
                : .localized(kind: .success, message: "锁记录 \(lockCount)", locale: locale, bundle: bundle, diagnostic: nil)
        default:
            return fallback
        }
    }
}

private extension MacSvnAuxiliaryFeedbackKind {
    var color: Color {
        switch colorRole {
        case .accent: .accentColor
        case .positive: .green
        case .caution: .orange
        case .negative: .red
        }
    }
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

enum MacSvnShelvePreviewRefreshPolicy {
    static func shouldEnqueuePreview(
        after outcome: MacSvnShelveLoadOutcome,
        hasSelection: Bool
    ) -> Bool {
        guard hasSelection else { return false }
        switch outcome {
        case .localFailure:
            return false
        case .officialFailure, .refreshed:
            return true
        }
    }
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

    static func loadFeedback(
        state: ShelveViewState?,
        officialError: String?,
        locale: Locale,
        bundle: LocalizedStringResource.BundleDescription = .main
    ) -> MacSvnAuxiliaryFeedback {
        switch loadOutcome(state: state, officialError: officialError) {
        case .localFailure(let diagnostic):
            let presented = MacSvnAuxiliaryErrorSummaryPresentation.message(diagnostic, locale: locale, bundle: bundle)
            return .localized(
                kind: .failure,
                message: "搁置记录加载失败：\(presented)",
                locale: locale,
                bundle: bundle,
                diagnostic: diagnostic
            )
        case .officialFailure(let diagnostic):
            let presented = MacSvnAuxiliaryErrorSummaryPresentation.message(diagnostic, locale: locale, bundle: bundle)
            return .localized(
                kind: .warning,
                message: "官方 shelf 列表加载失败：\(presented)",
                locale: locale,
                bundle: bundle,
                diagnostic: diagnostic
            )
        case .refreshed:
            return .localized(kind: .success, message: "已刷新搁置记录", locale: locale, bundle: bundle, diagnostic: nil)
        }
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
