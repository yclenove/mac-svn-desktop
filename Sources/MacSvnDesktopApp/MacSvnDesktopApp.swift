import SwiftUI
import MacSvnApp
import MacSvnCore

@main
struct MacSvnDesktopApplication: App {
    @StateObject private var bootstrap = MacSvnBootstrapModel()

    var body: some Scene {
        WindowGroup("MacSVN") {
            Group {
                switch bootstrap.phase {
                case .loading:
                    ProgressView("正在启动 MacSVN…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready(let session, let navigator, let menuBar):
                    MacSvnEnvironmentGateView(session: session, navigator: navigator)
                        .environmentObject(navigator)
                        .onAppear {
                            menuBar.start()
                            bootstrap.consumeLaunchArgumentsIfNeeded(navigator: navigator)
                        }
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
            .frame(minWidth: 980, minHeight: 640)
            .task {
                await bootstrap.start()
            }
            .onOpenURL { url in
                bootstrap.handleOpenURL(url)
            }
        }

        MenuBarExtra {
            if case .ready(_, let navigator, let menuBar) = bootstrap.phase {
                MacSvnMenuBarExtraContent(
                    menuBar: menuBar,
                    navigator: navigator
                )
            } else {
                Text("MacSVN 启动中…")
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
                MacSvnSettingsView(session: session)
            } else {
                MacSvnSettingsPlaceholderView()
            }
        }
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
        Button("打开工作副本") {
            navigator.selectedRoute = .workspace
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
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func handleOpenURL(_ url: URL) {
        guard case .ready(_, let navigator, _) = phase else { return }
        do {
            let action = try deepLinkParser.parse(url)
            navigator.handle(deepLink: action)
        } catch {
            navigator.lastAutomationMessage = "深链解析失败：\(error.localizedDescription)"
        }
    }

    func consumeLaunchArgumentsIfNeeded(navigator: MacSvnAppNavigator) {
        guard !didConsumeLaunchArguments else { return }
        didConsumeLaunchArguments = true

        // 跳过可执行路径本身，解析伴生 CLI：macsvn open|status|commit-ui …
        let args = Array(CommandLine.arguments.dropFirst())
        guard let first = args.first, !first.hasPrefix("-") else { return }
        do {
            let command = try cliParser.parse(args)
            navigator.handle(cli: command)
        } catch {
            // 非 CLI 启动参数时静默忽略，避免干扰正常 GUI 启动
        }
    }
}
