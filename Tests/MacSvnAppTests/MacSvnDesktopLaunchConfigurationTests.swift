import Foundation
import AppKit
import XCTest
@testable import MacSvnApp

final class MacSvnDesktopLaunchConfigurationTests: XCTestCase {
    func testRecognizesDeepLinkLaunchArgument() throws {
        let url = try XCTUnwrap(URL(string: "svnstudio://command?id=cmd.10.repoBrowser"))
        let configuration = MacSvnDesktopLaunchConfiguration(
            arguments: ["SVNStudio", url.absoluteString],
            environment: [:]
        )

        XCTAssertEqual(configuration.launchAction, .deepLink(url))
    }

    func testPreservesCompanionCLIArguments() {
        let configuration = MacSvnDesktopLaunchConfiguration(
            arguments: ["SVNStudio", "status", "/tmp/wc"],
            environment: [:]
        )

        XCTAssertEqual(configuration.launchAction, .cli(["status", "/tmp/wc"]))
    }

    func testIgnoresUITestOverridesUnlessExplicitlyEnabled() {
        let configuration = MacSvnDesktopLaunchConfiguration(
            arguments: ["SVNStudio"],
            environment: [
                "SVNSTUDIO_UI_TEST_WINDOW_SIZE": "980x640",
                "SVNSTUDIO_UI_TEST_APPEARANCE": "dark",
                "SVNSTUDIO_UI_TEST_REDUCE_MOTION": "1",
            ]
        )

        XCTAssertNil(configuration.windowSize)
        XCTAssertNil(configuration.appearance)
        XCTAssertNil(configuration.reduceMotion)
    }

    func testParsesUITestWindowAppearanceAndReduceMotionOverrides() {
        let configuration = MacSvnDesktopLaunchConfiguration(
            arguments: ["SVNStudio"],
            environment: [
                "SVNSTUDIO_UI_TESTING": "1",
                "SVNSTUDIO_UI_TEST_WINDOW_SIZE": "1440x900",
                "SVNSTUDIO_UI_TEST_APPEARANCE": "light",
                "SVNSTUDIO_UI_TEST_REDUCE_MOTION": "true",
            ]
        )

        XCTAssertEqual(configuration.windowSize, MacSvnWindowSize(width: 1_440, height: 900))
        XCTAssertEqual(configuration.appearance, .light)
        XCTAssertEqual(configuration.reduceMotion, true)
    }

    func testParsesUITestInitialRouteOnlyBehindExplicitGate() {
        let gated = MacSvnDesktopLaunchConfiguration(
            arguments: ["SVNStudio", "--ui-testing", "--ui-route=settings"],
            environment: [:]
        )
        let ungated = MacSvnDesktopLaunchConfiguration(
            arguments: ["SVNStudio", "--ui-route=settings"],
            environment: [:]
        )
        let unknown = MacSvnDesktopLaunchConfiguration(
            arguments: ["SVNStudio", "--ui-testing", "--ui-route=unknown"],
            environment: [:]
        )
        let camelCase = MacSvnDesktopLaunchConfiguration(
            arguments: ["SVNStudio", "--ui-testing", "--ui-route=revisionGraph"],
            environment: [:]
        )

        XCTAssertEqual(gated.initialRoute, .settings)
        XCTAssertEqual(camelCase.initialRoute, .revisionGraph)
        XCTAssertNil(ungated.initialRoute)
        XCTAssertNil(unknown.initialRoute)
    }

    func testParsesUITestOverridesFromLaunchServicesArguments() throws {
        let url = try XCTUnwrap(URL(string: "svnstudio://command?command=cmd.24.merge&path=/tmp/wc"))
        let configuration = MacSvnDesktopLaunchConfiguration(
            arguments: [
                "SVNStudio",
                url.absoluteString,
                "--ui-testing",
                "--ui-window-size=1180x760",
                "--ui-appearance=light",
                "--ui-reduce-motion=true",
            ],
            environment: [:]
        )

        XCTAssertEqual(configuration.launchAction, .deepLink(url))
        XCTAssertEqual(configuration.windowSize, MacSvnWindowSize(width: 1_180, height: 760))
        XCTAssertEqual(configuration.appearance, .light)
        XCTAssertEqual(configuration.reduceMotion, true)
    }

    func testRejectsMalformedOrUndersizedWindowOverrides() {
        for value in ["wide", "979x640", "980x639", "0x0"] {
            let configuration = MacSvnDesktopLaunchConfiguration(
                arguments: ["SVNStudio"],
                environment: [
                    "SVNSTUDIO_UI_TESTING": "1",
                    "SVNSTUDIO_UI_TEST_WINDOW_SIZE": value,
                ]
            )
            XCTAssertNil(configuration.windowSize, value)
        }
    }

    func testPendingDeepLinksDrainOnceInArrivalOrder() throws {
        let first = try XCTUnwrap(URL(string: "svnstudio://command?id=cmd.10.repoBrowser"))
        let second = try XCTUnwrap(URL(string: "svnstudio://command?id=cmd.24.merge"))
        var pending = MacSvnPendingDeepLinkBuffer()

        pending.enqueue(first)
        pending.enqueue(second)

        XCTAssertEqual(pending.drain(), [first, second])
        XCTAssertEqual(pending.drain(), [])
    }

    @MainActor
    func testWindowSizingViewAppliesRequestedContentSizeAfterAttachment() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let sizingView = MacSvnWindowSizingView(
            size: MacSvnWindowSize(width: 1_180, height: 760)
        )
        window.contentView?.addSubview(sizingView)

        try await Task.sleep(for: .milliseconds(250))

        let contentSize = try XCTUnwrap(window.contentView?.frame.size)
        XCTAssertEqual(contentSize.width, 1_180, accuracy: 0.5)
        XCTAssertEqual(contentSize.height, 760, accuracy: 0.5)
    }

    func testDeepLinkReadinessGateQueuesUntilWorkspaceIsReady() throws {
        let startup = try XCTUnwrap(URL(string: "svnstudio://command?command=cmd.10.repoBrowser&path=/tmp/wc"))
        let runtime = try XCTUnwrap(URL(string: "svnstudio://command?command=cmd.24.merge&path=/tmp/wc"))
        var gate = MacSvnDeepLinkReadinessGate()

        XCTAssertNil(gate.receive(startup))
        XCTAssertEqual(gate.markWorkspaceReady(), [startup])
        XCTAssertEqual(gate.receive(runtime), runtime)
        XCTAssertEqual(gate.markWorkspaceReady(), [])
    }
}
