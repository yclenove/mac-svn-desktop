import SwiftUI
import MacSvnCore

public struct MacSvnRootView: View {
    @ObservedObject private var session: MacSvnAppSession
    @ObservedObject private var navigator: MacSvnAppNavigator
    @StateObject private var workspaceController: MacSvnWorkspaceController
    private let sidebarModel: MacSvnSidebarModel
    @State private var showCommandPalette = false

    public init(
        session: MacSvnAppSession,
        navigator: MacSvnAppNavigator,
        sidebarModel: MacSvnSidebarModel = MacSvnSidebarModel()
    ) {
        self.session = session
        self.navigator = navigator
        self.sidebarModel = sidebarModel
        _workspaceController = StateObject(
            wrappedValue: MacSvnWorkspaceController(
                workspaceStore: session.workspaceStore,
                infoProvider: session.svnService
            )
        )
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: Binding(
                get: { navigator.selectedRoute },
                set: { navigator.selectedRoute = $0 ?? sidebarModel.defaultSelection }
            )) {
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
            VStack(alignment: .leading, spacing: 0) {
                if let message = navigator.lastAutomationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }
                MacSvnFeatureHostView(
                    route: navigator.selectedRoute,
                    session: session,
                    workspaceController: workspaceController,
                    navigator: navigator
                )
            }
        }
        .task {
            await workspaceController.reload()
            await consumePendingOpenIfNeeded()
        }
        .onChange(of: navigator.pendingOpenPath) { _, _ in
            Task { await consumePendingOpenIfNeeded() }
        }
        .sheet(isPresented: $showCommandPalette) {
            MacSvnCommandPaletteView(
                navigator: navigator,
                workspaceController: workspaceController,
                session: session,
                isPresented: $showCommandPalette
            )
        }
        .background {
            Button("") { showCommandPalette = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private func consumePendingOpenIfNeeded() async {
        guard let path = navigator.consumePendingOpenPath() else { return }
        await workspaceController.openLocalPath(path)
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
