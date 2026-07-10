import SwiftUI
import MacSvnApp

@main
struct MacSvnDesktopApplication: App {
    var body: some Scene {
        WindowGroup("MacSVN") {
            MacSvnRootView()
                .frame(minWidth: 980, minHeight: 640)
        }

        Settings {
            MacSvnSettingsPlaceholderView()
        }
    }
}
