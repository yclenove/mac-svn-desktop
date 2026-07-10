import SwiftUI
import MacSvnCore

/// 变更工作区：变更树 + Diff + 提交面板同屏。
/// 注意：避免嵌套 VSplitView+HSplitView + 海量子 View，否则 macOS SwiftUI 易陷入 AttributeGraph 死循环（CPU 100%）。
public struct MacSvnWorkingCopyWorkspaceView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession

    @State private var focusedDiffPath: String?
    @State private var seededSelection: Set<String> = []

    public init(
        workspaceController: MacSvnWorkspaceController,
        session: MacSvnAppSession,
        navigator: MacSvnAppNavigator
    ) {
        self.workspaceController = workspaceController
        self.session = session
        self.navigator = navigator
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                MacSvnChangesView(
                    workspaceController: workspaceController,
                    statusProvider: session.svnService,
                    navigator: navigator,
                    session: session,
                    embedded: true,
                    initialSelectedPaths: seededSelection,
                    onFocusedPathChange: { path in
                        guard path != focusedDiffPath else { return }
                        focusedDiffPath = path
                    }
                )
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)

                Divider()

                MacSvnDiffView(
                    workspaceController: workspaceController,
                    session: session,
                    navigator: navigator,
                    embedded: true,
                    externalSelectedPath: $focusedDiffPath
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            MacSvnCommitView(
                workspaceController: workspaceController,
                session: session,
                embedded: true
            )
            .frame(minHeight: 160, idealHeight: 200, maxHeight: 260)
        }
        .task {
            applyPendingDiffPathSeed()
        }
        .onChange(of: navigator.pendingDiffPath) { _, _ in
            applyPendingDiffPathSeed()
        }
    }

    private func applyPendingDiffPathSeed() {
        guard let path = navigator.pendingDiffPath else { return }
        seededSelection = [path]
        if focusedDiffPath != path {
            focusedDiffPath = path
        }
    }
}
