import SwiftUI
import MacSvnApp

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
                case .ready(let session):
                    MacSvnEnvironmentGateView(session: session)
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
        }

        Settings {
            if case .ready(let session) = bootstrap.phase {
                MacSvnSettingsView(session: session)
            } else {
                MacSvnSettingsPlaceholderView()
            }
        }
    }
}

@MainActor
final class MacSvnBootstrapModel: ObservableObject {
    enum Phase {
        case loading
        case ready(MacSvnAppSession)
        case failed(String)
    }

    @Published var phase: Phase = .loading

    func start() async {
        phase = .loading
        do {
            let session = try await MacSvnAppSession.bootstrap()
            phase = .ready(session)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
