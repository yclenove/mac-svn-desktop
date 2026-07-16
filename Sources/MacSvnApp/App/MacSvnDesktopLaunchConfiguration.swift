import AppKit
import Foundation
import SwiftUI

public enum MacSvnDesktopLaunchAction: Equatable, Sendable {
    case deepLink(URL)
    case cli([String])
}

public struct MacSvnWindowSize: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public enum MacSvnUITestAppearance: String, Equatable, Sendable {
    case light
    case dark

    fileprivate var colorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public struct MacSvnDesktopLaunchConfiguration: Equatable, Sendable {
    public let launchAction: MacSvnDesktopLaunchAction?
    public let windowSize: MacSvnWindowSize?
    public let appearance: MacSvnUITestAppearance?
    public let reduceMotion: Bool?
    public let initialRoute: MacSvnAppRoute?

    public init(arguments: [String], environment: [String: String]) {
        let rawPayload = Array(arguments.dropFirst())
        let payload = rawPayload.filter { !$0.hasPrefix("--ui-") }
        if let first = payload.first, !first.hasPrefix("-") {
            if let url = URL(string: first), url.scheme?.lowercased() == "svnstudio" {
                launchAction = .deepLink(url)
            } else {
                launchAction = .cli(payload)
            }
        } else {
            launchAction = nil
        }

        let isUITesting = environment["SVNSTUDIO_UI_TESTING"] == "1"
            || rawPayload.contains("--ui-testing")
        guard isUITesting else {
            windowSize = nil
            appearance = nil
            reduceMotion = nil
            initialRoute = nil
            return
        }

        windowSize = Self.parseWindowSize(
            Self.argumentValue("--ui-window-size", in: rawPayload)
                ?? environment["SVNSTUDIO_UI_TEST_WINDOW_SIZE"]
        )
        appearance = (
            Self.argumentValue("--ui-appearance", in: rawPayload)
                ?? environment["SVNSTUDIO_UI_TEST_APPEARANCE"]
        )
            .flatMap { MacSvnUITestAppearance(rawValue: $0.lowercased()) }
        reduceMotion = Self.parseBoolean(
            Self.argumentValue("--ui-reduce-motion", in: rawPayload)
                ?? environment["SVNSTUDIO_UI_TEST_REDUCE_MOTION"]
        )
        initialRoute = (
            Self.argumentValue("--ui-route", in: rawPayload)
                ?? environment["SVNSTUDIO_UI_TEST_ROUTE"]
        )
            .flatMap(MacSvnAppRoute.init(rawValue:))
    }

    public static func current() -> MacSvnDesktopLaunchConfiguration {
        MacSvnDesktopLaunchConfiguration(
            arguments: CommandLine.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }

    private static func parseWindowSize(_ value: String?) -> MacSvnWindowSize? {
        guard let value else { return nil }
        let dimensions = value.lowercased().split(separator: "x", omittingEmptySubsequences: false)
        guard dimensions.count == 2,
              let width = Int(dimensions[0]),
              let height = Int(dimensions[1]),
              width >= 980,
              height >= 640
        else { return nil }
        return MacSvnWindowSize(width: width, height: height)
    }

    private static func argumentValue(_ name: String, in arguments: [String]) -> String? {
        let prefix = name + "="
        return arguments.first(where: { $0.hasPrefix(prefix) }).map {
            String($0.dropFirst(prefix.count))
        }
    }

    private static func parseBoolean(_ value: String?) -> Bool? {
        switch value?.lowercased() {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }
}

public struct MacSvnPendingDeepLinkBuffer: Sendable {
    private var urls: [URL] = []

    public init() {}

    public mutating func enqueue(_ url: URL) {
        urls.append(url)
    }

    public mutating func drain() -> [URL] {
        defer { urls.removeAll(keepingCapacity: true) }
        return urls
    }
}

public struct MacSvnDeepLinkReadinessGate: Sendable {
    private var isWorkspaceReady = false
    private var pending = MacSvnPendingDeepLinkBuffer()

    public init() {}

    public mutating func receive(_ url: URL) -> URL? {
        guard isWorkspaceReady else {
            pending.enqueue(url)
            return nil
        }
        return url
    }

    public mutating func markWorkspaceReady() -> [URL] {
        guard !isWorkspaceReady else { return [] }
        isWorkspaceReady = true
        return pending.drain()
    }
}

private struct MacSvnReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var macSvnReduceMotionOverride: Bool? {
        get { self[MacSvnReduceMotionOverrideKey.self] }
        set { self[MacSvnReduceMotionOverrideKey.self] = newValue }
    }
}

/// Applies deterministic UI evidence settings only when the explicit test gate is enabled.
public struct MacSvnLaunchConfiguredContent<Content: View>: View {
    private let configuration: MacSvnDesktopLaunchConfiguration
    private let content: () -> Content

    public init(
        configuration: MacSvnDesktopLaunchConfiguration,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.configuration = configuration
        self.content = content
    }

    public var body: some View {
        content()
            .preferredColorScheme(configuration.appearance?.colorScheme)
            .environment(\.macSvnReduceMotionOverride, configuration.reduceMotion)
            .transaction { transaction in
                if configuration.reduceMotion == true {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .background {
                MacSvnWindowSizeApplicator(size: configuration.windowSize)
                    .frame(width: 0, height: 0)
            }
    }
}

private struct MacSvnWindowSizeApplicator: NSViewRepresentable {
    let size: MacSvnWindowSize?

    func makeNSView(context: Context) -> MacSvnWindowSizingView {
        MacSvnWindowSizingView(size: size)
    }

    func updateNSView(_ nsView: MacSvnWindowSizingView, context: Context) {
        nsView.update(size: size)
    }
}

@MainActor
final class MacSvnWindowSizingView: NSView {
    private var targetSize: MacSvnWindowSize?
    private var appliedSize: MacSvnWindowSize?
    private var applicationGeneration = 0

    init(size: MacSvnWindowSize?) {
        targetSize = size
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        appliedSize = nil
        scheduleApplication()
    }

    func update(size: MacSvnWindowSize?) {
        if targetSize != size {
            appliedSize = nil
        }
        targetSize = size
        scheduleApplication()
    }

    private func scheduleApplication() {
        applicationGeneration &+= 1
        let generation = applicationGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.applicationGeneration == generation else { return }
            self.applyIfNeeded()
        }
    }

    private func applyIfNeeded() {
        guard let targetSize, targetSize != appliedSize, let window else { return }
        window.setContentSize(NSSize(width: targetSize.width, height: targetSize.height))
        appliedSize = targetSize
    }
}
