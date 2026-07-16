import SwiftUI
import MacSvnApp
import MacSvnCore

@main
struct MacSvnDesktopApplication: App {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var bootstrap = MacSvnBootstrapModel()
    private let launchConfiguration = MacSvnDesktopLaunchConfiguration.current()

    var body: some Scene {
        WindowGroup(ProductBranding.displayName) {
            MacSvnLaunchConfiguredContent(configuration: launchConfiguration) {
                Group {
                    switch bootstrap.phase {
                    case .loading:
                        ProgressView("正在启动 \(ProductBranding.displayName)…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .ready(let session, let navigator, let menuBar):
                        MacSvnLocalizedSessionView(
                            session: session,
                            navigator: navigator,
                            menuBar: menuBar,
                            onWorkspaceReady: {
                                bootstrap.consumeLaunchArgumentsIfNeeded(
                                    launchConfiguration,
                                    navigator: navigator
                                )
                            }
                        )
                    case .failed(let message):
                        VStack(spacing: 12) {
                            Text("启动失败")
                                .font(.title2.weight(.semibold))
                            Text(message)
                                .foregroundStyle(.secondary)
                            Button("重试") {
                                Task { await bootstrap.start() }
                            }
                        }
                        .padding(40)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(minWidth: 980, minHeight: 640)
            .task {
                await bootstrap.start()
            }
            .onOpenURL { url in
                bootstrap.handleOpenURL(url)
            }
        }
        .defaultSize(width: 1_180, height: 760)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button {
                    openWindow(id: ProductBranding.aboutWindowID)
                } label: {
                    Text(LocalizedStringKey(ProductBranding.aboutWindowTitle))
                }
            }
        }

        Window(LocalizedStringKey(ProductBranding.aboutWindowTitle), id: ProductBranding.aboutWindowID) {
            if case .ready(let session, _, _) = bootstrap.phase {
                MacSvnLocalizedContent(session: session) {
                    MacSvnAboutView()
                }
            } else {
                MacSvnAboutView()
            }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        MenuBarExtra {
            if case .ready(let session, let navigator, let menuBar) = bootstrap.phase {
                MacSvnLocalizedContent(session: session) {
                    MacSvnMenuBarExtraContent(
                        menuBar: menuBar,
                        navigator: navigator
                    )
                }
            } else {
                Text("\(ProductBranding.displayName) 启动中…")
            }
        } label: {
            if case .ready(_, _, let menuBar) = bootstrap.phase {
                MacSvnMenuBarLabel(menuBar: menuBar)
            } else {
                Label("SVN", systemImage: "externaldrive.badge.timemachine")
            }
        }

        Settings {
            if case .ready(let session, _, _) = bootstrap.phase {
                MacSvnLocalizedContent(session: session) {
                    MacSvnSettingsView(session: session)
                }
            } else {
                MacSvnSettingsLoadingView()
            }
        }
    }

}

struct MacSvnLocalizedSessionView: View {
    @ObservedObject var session: MacSvnAppSession
    let navigator: MacSvnAppNavigator
    let menuBar: MacSvnMenuBarController
    let onWorkspaceReady: () -> Void

    var body: some View {
        MacSvnLocalizedContent(session: session) {
            MacSvnEnvironmentGateView(
                session: session,
                navigator: navigator,
                onWorkspaceReady: onWorkspaceReady
            )
                .environmentObject(navigator)
        }
            .onAppear {
                menuBar.start()
            }
    }
}

struct MacSvnLocalizedContent<Content: View>: View {
    @ObservedObject var session: MacSvnAppSession
    private let content: () -> Content

    init(
        session: MacSvnAppSession,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.session = session
        self.content = content
    }

    var body: some View {
        content()
            .environment(\.locale, selectedLocale)
    }

    private var selectedLocale: Locale {
        session.settingsSnapshot.general.language.localeIdentifier
            .map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }
}

struct MacSvnMenuBarLabel: View {
    @ObservedObject var menuBar: MacSvnMenuBarController

    var body: some View {
        Label(menuBar.badgeText, systemImage: "externaldrive.badge.timemachine")
    }
}

struct MacSvnMenuBarExtraContent: View {
    @ObservedObject var menuBar: MacSvnMenuBarController
    @ObservedObject var navigator: MacSvnAppNavigator

    var body: some View {
        if let snapshot = menuBar.snapshot {
            Text("本地变更 \(snapshot.totalLocalChangeCount) / 远端新提交 \(snapshot.totalRemoteNewCommitCount)")
            Divider()
            ForEach(snapshot.workingCopies, id: \.recordID) { item in
                Button("\(item.name)：本地 \(item.localChangeCount)，远端 +\(item.remoteNewCommitCount)") {
                    navigator.handle(cli: .status(path: item.localPath))
                }
            }
        } else {
            Text("尚未刷新状态")
        }
        Divider()
        Button("立即刷新") {
            Task { await menuBar.refresh() }
        }
        Button("打开变更工作区") {
            navigator.selectMode(.changes)
        }
        if let error = menuBar.lastError {
            Text(error)
                .foregroundStyle(.red)
        }
    }
}

@MainActor
final class MacSvnBootstrapModel: ObservableObject {
    enum Phase {
        case loading
        case ready(MacSvnAppSession, MacSvnAppNavigator, MacSvnMenuBarController)
        case failed(String)
    }

    @Published var phase: Phase = .loading
    private var didConsumeLaunchArguments = false
    private var deepLinkReadinessGate = MacSvnDeepLinkReadinessGate()
    private let deepLinkParser = MacSvnDeepLinkParser()
    private let cliParser = MacSvnCLICommandParser()

    func start() async {
        phase = .loading
        do {
            let session = try await MacSvnAppSession.bootstrap()
            let navigator = MacSvnAppNavigator()
            let menuBar = MacSvnMenuBarController(
                workspaceStore: session.workspaceStore,
                snapshotter: session.menuBarStatusSnapshotter,
                pollIntervalMinutes: session.menuBarPollIntervalMinutes
            )
            phase = .ready(session, navigator, menuBar)
            if session.settingsSnapshot.general.checkForUpdatesAutomatically {
                Task { await session.checkForUpdates() }
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func handleOpenURL(_ url: URL) {
        guard let readyURL = deepLinkReadinessGate.receive(url),
              case .ready(_, let navigator, _) = phase
        else { return }
        processOpenURL(readyURL, navigator: navigator)
    }

    private func processOpenURL(_ url: URL, navigator: MacSvnAppNavigator) {
        do {
            let action = try deepLinkParser.parse(url)
            navigator.handle(deepLink: action)
        } catch {
            navigator.lastAutomationMessage = "深链解析失败：\(error.localizedDescription)"
        }
    }

    private func consumePendingDeepLinks(navigator: MacSvnAppNavigator) {
        for url in deepLinkReadinessGate.markWorkspaceReady() {
            processOpenURL(url, navigator: navigator)
        }
    }

    func consumeLaunchArgumentsIfNeeded(
        _ configuration: MacSvnDesktopLaunchConfiguration,
        navigator: MacSvnAppNavigator
    ) {
        guard !didConsumeLaunchArguments else { return }
        didConsumeLaunchArguments = true
        if let initialRoute = configuration.initialRoute {
            navigator.selectRoute(initialRoute)
        }
        consumePendingDeepLinks(navigator: navigator)

        switch configuration.launchAction {
        case .deepLink(let url):
            processOpenURL(url, navigator: navigator)
        case .cli(let arguments):
            do {
                let command = try cliParser.parse(arguments)
                navigator.handle(cli: command)
            } catch {
                // 非 CLI 启动参数时静默忽略，避免干扰正常 GUI 启动
            }
        case .none:
            break
        }
    }
}
