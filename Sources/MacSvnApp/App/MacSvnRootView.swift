import SwiftUI

public struct MacSvnRootView: View {
    private let sidebarModel: MacSvnSidebarModel
    @State private var selection: MacSvnAppRoute?

    public init(sidebarModel: MacSvnSidebarModel = MacSvnSidebarModel()) {
        self.sidebarModel = sidebarModel
        _selection = State(initialValue: sidebarModel.defaultSelection)
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
            MacSvnRoutePlaceholderView(route: selection ?? sidebarModel.defaultSelection)
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
            LabeledContent("配置", value: "准备就绪")
        }
        .padding()
        .frame(width: 420)
    }
}
