import SwiftUI
import MacSvnCore

/// 按路由分发到真实功能页；尚未接线的路由保留占位，避免阻塞导航。
public struct MacSvnFeatureHostView: View {
    public let route: MacSvnAppRoute
    @ObservedObject public var session: MacSvnAppSession
    @ObservedObject public var workspaceController: MacSvnWorkspaceController
    @ObservedObject public var navigator: MacSvnAppNavigator

    public init(
        route: MacSvnAppRoute,
        session: MacSvnAppSession,
        workspaceController: MacSvnWorkspaceController,
        navigator: MacSvnAppNavigator
    ) {
        self.route = route
        self.session = session
        self.workspaceController = workspaceController
        self.navigator = navigator
    }

    public var body: some View {
        switch route {
        case .workspace:
            MacSvnWorkspaceView(controller: workspaceController)
        case .changes:
            MacSvnChangesView(
                workspaceController: workspaceController,
                statusProvider: session.svnService,
                navigator: navigator
            )
        case .commit:
            MacSvnCommitView(workspaceController: workspaceController, session: session)
        case .diff:
            MacSvnDiffView(workspaceController: workspaceController, session: session, navigator: navigator)
        case .log:
            MacSvnLogView(workspaceController: workspaceController, session: session, navigator: navigator)
        case .repositoryBrowser:
            MacSvnRepoBrowserView(session: session, workspaceController: workspaceController)
        case .branches:
            MacSvnBranchesView(workspaceController: workspaceController, session: session)
        case .merge:
            MacSvnConflictWorkspaceView(workspaceController: workspaceController, session: session)
        case .blame:
            MacSvnBlameView(workspaceController: workspaceController, session: session)
        case .properties:
            MacSvnPropertiesView(workspaceController: workspaceController, session: session)
        case .locks:
            MacSvnLocksView(workspaceController: workspaceController, session: session)
        case .shelve:
            MacSvnShelveView(workspaceController: workspaceController, session: session)
        case .gitMigration:
            MacSvnGitMigrationView(workspaceController: workspaceController, session: session)
        case .teamActivity:
            MacSvnTeamActivityView(workspaceController: workspaceController, session: session)
        case .aiAssistant:
            MacSvnAIAssistantView(workspaceController: workspaceController, session: session)
        case .settings:
            MacSvnSettingsView(session: session)
        }
    }
}
