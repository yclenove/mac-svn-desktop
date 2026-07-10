import SwiftUI
import MacSvnCore

/// 变更工作区：变更树 + Diff + 提交面板同屏（Wave U2）。
public struct MacSvnWorkingCopyWorkspaceView: View {
    @ObservedObject private var workspaceController: MacSvnWorkspaceController
    @ObservedObject private var navigator: MacSvnAppNavigator
    private let session: MacSvnAppSession

    @State private var focusedDiffPath: String?
    /// 供变更树与深链共同驱动的选中路径。
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
        VSplitView {
            HSplitView {
                MacSvnChangesView(
                    workspaceController: workspaceController,
                    statusProvider: session.svnService,
                    navigator: navigator,
                    session: session,
                    embedded: true,
                    initialSelectedPaths: seededSelection,
                    onFocusedPathChange: { path in
                        focusedDiffPath = path
                    }
                )
                .frame(minWidth: 280)
                .id(seededSelection) // 深链注入选中时重建，确保 List selection 生效

                MacSvnDiffView(
                    workspaceController: workspaceController,
                    session: session,
                    navigator: navigator,
                    embedded: true,
                    externalSelectedPath: $focusedDiffPath
                )
                .frame(minWidth: 320)
            }
            .frame(minHeight: 280)

            MacSvnCommitView(
                workspaceController: workspaceController,
                session: session,
                embedded: true
            )
            .frame(minHeight: 180)
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
        focusedDiffPath = path
    }
}
