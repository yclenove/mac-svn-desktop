import SwiftUI
import MacSvnCore

/// 按路由分发到真实功能页；尚未接线的路由保留占位，避免阻塞导航。
public struct MacSvnFeatureHostView: View {
    public let route: MacSvnAppRoute
    @ObservedObject public var session: MacSvnAppSession
    @ObservedObject public var workspaceController: MacSvnWorkspaceController

    public init(
        route: MacSvnAppRoute,
        session: MacSvnAppSession,
        workspaceController: MacSvnWorkspaceController
    ) {
        self.route = route
        self.session = session
        self.workspaceController = workspaceController
    }

    public var body: some View {
        switch route {
        case .workspace:
            MacSvnWorkspaceView(controller: workspaceController)
        case .changes:
            MacSvnChangesView(
                workspaceController: workspaceController,
                statusProvider: session.svnService
            )
        case .commit:
            MacSvnCommitView(workspaceController: workspaceController, session: session)
        case .diff:
            MacSvnDiffView(workspaceController: workspaceController, svnService: session.svnService)
        case .log:
            MacSvnLogView(workspaceController: workspaceController, session: session)
        case .repositoryBrowser:
            MacSvnRepoBrowserView(session: session, workspaceController: workspaceController)
        case .branches:
            MacSvnBranchesView(workspaceController: workspaceController, session: session)
        case .merge:
            // 路由标题为「冲突合并」：Wave C 先接 Merge 向导；Wave D 再叠冲突列表/编辑器
            MacSvnMergeWizardView(workspaceController: workspaceController, session: session)
        case .settings:
            MacSvnSettingsView(session: session)
        default:
            MacSvnRoutePlaceholderView(route: route)
        }
    }
}
