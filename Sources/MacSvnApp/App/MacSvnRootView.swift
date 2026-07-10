import SwiftUI
import MacSvnCore

public struct MacSvnRootView: View {
    @ObservedObject private var session: MacSvnAppSession
    @StateObject private var workspaceController: MacSvnWorkspaceController
    private let sidebarModel: MacSvnSidebarModel
    @State private var selection: MacSvnAppRoute?

    public init(
        session: MacSvnAppSession,
        sidebarModel: MacSvnSidebarModel = MacSvnSidebarModel()
    ) {
        self.session = session
        self.sidebarModel = sidebarModel
        _selection = State(initialValue: sidebarModel.defaultSelection)
        _workspaceController = StateObject(
            wrappedValue: MacSvnWorkspaceController(
                workspaceStore: session.workspaceStore,
                infoProvider: session.svnService
            )
        )
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(sidebarModel.sections) { sidebarSection in
                    Section(sidebarSection.section.title) {
                        ForEach(sidebarSection.routes) { route in
                            Label(route.title, systemImage: route.systemImage)
                                .tag(route)
                        }
                    }
                }
            }
            .navigationTitle("MacSVN")
        } detail: {
            MacSvnFeatureHostView(
                route: selection ?? sidebarModel.defaultSelection,
                session: session,
                workspaceController: workspaceController
            )
        }
    }
}

public struct MacSvnRoutePlaceholderView: View {
    public let route: MacSvnAppRoute

    public init(route: MacSvnAppRoute) {
        self.route = route
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: route.systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 6) {
                Text(route.title)
                    .font(.largeTitle.weight(.semibold))
                Text(route.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("功能页接线中（长程 Loop 将按 backlog 逐项替换占位）")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(40)
        .navigationTitle(route.title)
    }
}

public struct MacSvnSettingsPlaceholderView: View {
    public init() {}

    public var body: some View {
        Form {
            LabeledContent("应用", value: "MacSVN")
            LabeledContent("配置", value: "请从主窗口打开「设置」路由")
        }
        .padding()
        .frame(width: 420)
    }
}
